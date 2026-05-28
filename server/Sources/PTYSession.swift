// server/Sources/PTYSession.swift
import Foundation
import Darwin
import MaverickProtocol

final class PTYSession: @unchecked Sendable {
    let info: SessionInfo
    private var masterFd: Int32 = -1
    private var childPid: pid_t = -1
    private var source: DispatchSourceRead?
    private var scrollback = CircularBuffer<UInt8>(capacity: 1_048_576) // 1MB
    private let lock = NSLock()
    private var observers: [(id: UUID, handler: (Data) -> Void)] = []
    var onExit: (() -> Void)?

    private let cwd: String?
    /// Temp directory holding the per-shell integration rcfile/config. Cleaned
    /// up on terminate().
    private var integrationTempDir: URL?

    init(name: String, shell: String = "/bin/zsh", cwd: String? = nil) {
        self.info = SessionInfo(name: name, shell: shell)
        self.cwd = cwd
    }

    func start() throws {
        guard masterFd < 0 else { return }
        var ws = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0

        // Build shell integration (rcfile + env) in the PARENT before fork.
        // Doing this pre-fork keeps the post-fork child path async-signal-safe.
        let integration = Self.buildShellIntegration(shell: info.shell)
        integrationTempDir = integration.tempDir
        let argvStrings = [info.shell] + integration.extraArgs
        let envStrings = integration.envEntries

        // Pre-build argv + envp C pointer arrays in the parent so the child
        // only has to call execve. strdup, setenv, chdir, execve are all
        // async-signal-safe per POSIX.
        let argvPtrs: [UnsafeMutablePointer<CChar>?] =
            argvStrings.map { strdup($0) } + [nil]
        let envpPtrs: [UnsafeMutablePointer<CChar>?] =
            envStrings.map { strdup($0) } + [nil]

        childPid = forkpty(&master, nil, nil, &ws)
        guard childPid >= 0 else { throw PTYError.forkFailed(errno) }

        if childPid == 0 {
            // chdir before exec so the shell starts in the chosen directory.
            let resolved = Self.resolveStartDirectory(requested: cwd)
            if let resolved {
                resolved.withCString { _ = chdir($0) }
            }

            // execve replaces process image; pass our prepared argv + envp.
            var argv = argvPtrs
            var envp = envpPtrs
            _ = execve(info.shell, &argv, &envp)
            _exit(1)
        }

        masterFd = master
        source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: .global())
        source?.setEventHandler { [weak self] in self?.readOutput() }
        source?.setCancelHandler { [weak self] in self?.closeFd() }
        source?.resume()
    }

    private func readOutput() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(masterFd, &buf, buf.count)
        guard n > 0 else {
            if childPid > 0 {
                var status: Int32 = 0
                _ = waitpid(childPid, &status, WNOHANG)
                childPid = -1
            }
            source?.cancel()
            onExit?()
            return
        }
        let data = Data(buf[0..<n])
        lock.lock()
        scrollback.append(contentsOf: buf[0..<n])
        let obs = observers
        lock.unlock()
        obs.forEach { $0.handler(data) }
    }

    func write(_ data: Data) {
        guard masterFd >= 0 else { return }
        data.withUnsafeBytes { _ = Foundation.write(masterFd, $0.baseAddress, data.count) }
    }

    func resize(cols: UInt16, rows: UInt16) {
        guard masterFd >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }

    func getScrollback() -> Data {
        lock.lock(); defer { lock.unlock() }
        return Data(scrollback.snapshot())
    }

    func addObserver(id: UUID, handler: @escaping (Data) -> Void) {
        lock.lock(); defer { lock.unlock() }
        observers.append((id: id, handler: handler))
    }

    func removeObserver(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        observers.removeAll { $0.id == id }
    }

    func terminate() {
        if childPid > 0 {
            let pid = childPid
            childPid = -1
            kill(pid, SIGTERM)
            // Async escalation to SIGKILL if SIGTERM is ignored.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == 0 {
                    kill(pid, SIGKILL)
                    _ = waitpid(pid, &status, 0)
                }
            }
        }
        source?.cancel()
        cleanupIntegrationDir()
    }

    private func cleanupIntegrationDir() {
        guard let dir = integrationTempDir else { return }
        integrationTempDir = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func closeFd() {
        if masterFd >= 0 { close(masterFd); masterFd = -1 }
    }

    /// Resolves the working directory for a new session:
    ///   - If `requested` is set, expand a leading `~` and use it.
    ///   - Otherwise, fall back to the user's $HOME.
    /// Note: this runs in the parent before fork as well as in the child
    /// after fork (the result is captured by the child via the `cwd` field),
    /// so the string itself is computed pre-fork. The actual `chdir` call
    /// happens post-fork using only async-signal-safe APIs.
    private static func resolveStartDirectory(requested: String?) -> String? {
        let home = String(cString: getenv("HOME") ?? UnsafeMutablePointer<CChar>(mutating: ""))
        guard let req = requested?.trimmingCharacters(in: .whitespacesAndNewlines), !req.isEmpty else {
            return home.isEmpty ? nil : home
        }
        if req == "~" { return home.isEmpty ? nil : home }
        if req.hasPrefix("~/") { return home + String(req.dropFirst(1)) }
        return req
    }

    enum PTYError: Error { case forkFailed(Int32) }

    // MARK: - Shell integration

    private struct ShellIntegration {
        let tempDir: URL?
        let extraArgs: [String]
        let envEntries: [String]
    }

    /// Writes a per-session rcfile that re-sources the user's normal shell
    /// init, then adds an OSC 7 prompt hook so we can follow `cd`. Returns
    /// argv extras and env-vars-as-`KEY=VALUE` strings to feed execve.
    ///
    /// The hook is in place BEFORE the first prompt is painted — no flashing
    /// setup commands, no `clear` hack.
    private static func buildShellIntegration(shell: String) -> ShellIntegration {
        let baseName = (shell as NSString).lastPathComponent.lowercased()
        let parentEnv = ProcessInfo.processInfo.environment
        let parentEnvAsStrings = parentEnv.map { "\($0.key)=\($0.value)" }

        guard let tempDir = makeTempDir() else {
            return ShellIntegration(tempDir: nil, extraArgs: ["-l"], envEntries: parentEnvAsStrings)
        }

        switch baseName {
        case "zsh":
            // Override ZDOTDIR so zsh reads our .zshrc (which sources the
            // user's profile + .zshrc, then installs the OSC 7 hook).
            let rc = """
            # Maverick shell integration — auto-generated
            [ -f "$HOME/.zprofile" ] && emulate sh -c 'source "$HOME/.zprofile"' 2>/dev/null
            [ -f "$HOME/.zshrc" ]    && source "$HOME/.zshrc"
            typeset -ga precmd_functions
            _maverick_emit_cwd() {
                printf '\\e]7;file://%s%s\\e\\\\' "${HOST:-localhost}" "$PWD"
            }
            precmd_functions+=(_maverick_emit_cwd)
            _maverick_emit_cwd
            """
            try? rc.write(to: tempDir.appendingPathComponent(".zshrc"),
                          atomically: true, encoding: .utf8)
            // Also write an empty .zlogin/.zprofile in temp dir so zsh's
            // login phase doesn't fall back to system files unexpectedly.
            try? "".write(to: tempDir.appendingPathComponent(".zlogin"),
                          atomically: true, encoding: .utf8)
            var env = parentEnv
            env["ZDOTDIR"] = tempDir.path
            return ShellIntegration(
                tempDir: tempDir,
                extraArgs: ["-l"],
                envEntries: env.map { "\($0.key)=\($0.value)" }
            )

        case "bash":
            // Pass --rcfile <tmp>/bashrc; the rcfile sources user's normal
            // bashrc/profile and registers a PROMPT_COMMAND hook.
            let rc = """
            # Maverick shell integration — auto-generated
            if [ -f "$HOME/.bash_profile" ]; then
                source "$HOME/.bash_profile"
            elif [ -f "$HOME/.profile" ]; then
                source "$HOME/.profile"
            fi
            [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
            _maverick_emit_cwd() {
                printf '\\e]7;file://%s%s\\e\\\\' "${HOSTNAME:-localhost}" "$PWD"
            }
            PROMPT_COMMAND="_maverick_emit_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
            _maverick_emit_cwd
            """
            let rcPath = tempDir.appendingPathComponent("bashrc")
            try? rc.write(to: rcPath, atomically: true, encoding: .utf8)
            return ShellIntegration(
                tempDir: tempDir,
                extraArgs: ["--rcfile", rcPath.path, "-i"],
                envEntries: parentEnvAsStrings
            )

        case "fish":
            // fish reads $XDG_CONFIG_HOME/fish/config.fish on startup.
            let fishConfDir = tempDir.appendingPathComponent("fish", isDirectory: true)
            try? FileManager.default.createDirectory(at: fishConfDir, withIntermediateDirectories: true)
            let conf = """
            # Maverick shell integration — auto-generated
            if test -f "$HOME/.config/fish/config.fish"
                source "$HOME/.config/fish/config.fish"
            end
            function __maverick_emit_cwd --on-event fish_prompt
                printf '\\e]7;file://%s%s\\e\\\\' (hostname) $PWD
            end
            __maverick_emit_cwd
            """
            try? conf.write(to: fishConfDir.appendingPathComponent("config.fish"),
                            atomically: true, encoding: .utf8)
            var env = parentEnv
            env["XDG_CONFIG_HOME"] = tempDir.path
            return ShellIntegration(
                tempDir: tempDir,
                extraArgs: ["-l"],
                envEntries: env.map { "\($0.key)=\($0.value)" }
            )

        default:
            // Unknown shell — preserve previous behaviour (login, no hook).
            return ShellIntegration(tempDir: tempDir, extraArgs: ["-l"], envEntries: parentEnvAsStrings)
        }
    }

    private static func makeTempDir() -> URL? {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("maverick-shell-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        } catch {
            return nil
        }
    }
}
