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

    init(name: String, shell: String = "/bin/zsh", cwd: String? = nil) {
        self.info = SessionInfo(name: name, shell: shell)
        self.cwd = cwd
    }

    func start() throws {
        guard masterFd < 0 else { return }
        var ws = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0
        childPid = forkpty(&master, nil, nil, &ws)
        guard childPid >= 0 else { throw PTYError.forkFailed(errno) }

        if childPid == 0 {
            // chdir before exec so the shell starts in the chosen directory.
            // Both getenv and chdir are async-signal-safe per POSIX, so they
            // are safe to call between fork and exec.
            let resolved = Self.resolveStartDirectory(requested: cwd)
            if let resolved {
                resolved.withCString { _ = chdir($0) }
            }

            let shell = info.shell
            // execv is non-variadic; safe to call from Swift.
            // argv must be a null-terminated array of C strings.
            shell.withCString { shellPtr in
                "-l".withCString { loginFlag in
                    var argv: [UnsafeMutablePointer<CChar>?] = [
                        strdup(shellPtr),
                        strdup(loginFlag),
                        nil
                    ]
                    _ = execv(shellPtr, &argv)
                }
            }
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
}
