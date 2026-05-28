// server/Sources/AgentSession.swift
import Foundation
import MaverickProtocol

/// A mode-aware session that wraps `PTYSession` (terminal mode) or spawns a
/// provider CLI subprocess (chat mode) and funnels output through an
/// `AgentEventNormalizing` adapter.
final class AgentSession: @unchecked Sendable {

    // MARK: - Public identity

    let sessionId: UUID
    let provider: AgentProvider
    private(set) var mode: SessionMode

    // MARK: - Callbacks

    /// Called for every normalized `AgentEvent` (chat mode).
    var onAgentEvent: ((AgentEvent) -> Void)?

    /// Called for every raw output byte chunk (terminal mode passthrough).
    var onRawOutput: ((Data) -> Void)?

    /// Called when the underlying process/PTY exits.
    var onExit: (() -> Void)?

    // MARK: - Internal state

    /// Terminal mode delegate.
    private var ptySession: PTYSession?

    /// Chat mode process.
    private var agentProcess: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?

    private let normalizer: AgentEventNormalizing
    private let cwd: String?

    /// Session ID returned by Claude Code's SessionStart hook — used for --continue.
    private var claudeSessionId: String?

    private let lock = NSLock()
    private let outputQueue = DispatchQueue(label: "AgentSession.output", qos: .utility)

    // MARK: - Init

    init(
        sessionId: UUID,
        provider: AgentProvider,
        mode: SessionMode,
        normalizer: AgentEventNormalizing,
        cwd: String? = nil
    ) {
        self.sessionId = sessionId
        self.provider = provider
        self.mode = mode
        self.normalizer = normalizer
        self.cwd = cwd
    }

    // MARK: - Lifecycle

    /// Start the session in the current mode.
    func start() throws {
        switch mode {
        case .terminal:
            try startTerminal()
        case .chat:
            try startChat()
        }
    }

    /// Switch between terminal and chat mode.
    /// In chat mode, uses `--continue` (or `-c`) if `claudeSessionId` is known.
    func switchMode(to newMode: SessionMode) throws {
        guard newMode != mode else { return }
        terminate()
        mode = newMode
        try start()
    }

    /// Send text input to the agent.
    /// - Terminal mode: write bytes to the PTY master.
    /// - Chat mode: write UTF-8 text + newline to process stdin.
    func sendInput(_ text: String) {
        switch mode {
        case .terminal:
            guard let data = text.data(using: .utf8) else { return }
            ptySession?.write(data)
        case .chat:
            guard let stdinPipe,
                  let data = (text + "\n").data(using: .utf8)
            else { return }
            stdinPipe.fileHandleForWriting.write(data)
        }
    }

    // MARK: - Terminal passthrough

    func resize(cols: UInt16, rows: UInt16) {
        ptySession?.resize(cols: cols, rows: rows)
    }

    func getScrollback() -> Data {
        ptySession?.getScrollback() ?? Data()
    }

    func addObserver(id: UUID, handler: @escaping (Data) -> Void) {
        ptySession?.addObserver(id: id, handler: handler)
    }

    func removeObserver(id: UUID) {
        ptySession?.removeObserver(id: id)
    }

    // MARK: - Termination

    func terminate() {
        // Terminal mode
        ptySession?.terminate()
        ptySession = nil

        // Chat mode
        agentProcess?.terminate()
        agentProcess = nil

        // Close stdin so the child process sees EOF
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        stdoutPipe = nil
    }

    // MARK: - Private: terminal launch

    private func startTerminal() throws {
        let name = "agent-\(sessionId.uuidString.prefix(8))"
        let pty = PTYSession(name: name, shell: "/bin/zsh", cwd: cwd)
        pty.onExit = { [weak self] in
            self?.onExit?()
        }
        // Route all raw PTY bytes through onRawOutput
        pty.addObserver(id: sessionId) { [weak self] data in
            self?.onRawOutput?(data)
        }
        try pty.start()
        ptySession = pty
    }

    // MARK: - Private: chat launch

    private func startChat() throws {
        let (executablePath, arguments) = launchCommand()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Set working directory
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Inherit parent environment so PATH / API keys are available
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipeLocal = Pipe()
        let stdinPipeLocal = Pipe()
        process.standardOutput = stdoutPipeLocal
        process.standardInput = stdinPipeLocal
        // Suppress stderr to avoid noise; could redirect to a log in the future
        process.standardError = Pipe()

        process.terminationHandler = { [weak self] _ in
            self?.onExit?()
        }

        // Read stdout line-by-line on background queue
        stdoutPipeLocal.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.processOutput(data)
        }

        try process.run()

        agentProcess = process
        stdoutPipe = stdoutPipeLocal
        stdinPipe = stdinPipeLocal
    }

    /// Returns (executablePath, arguments) for the provider's CLI.
    private func launchCommand() -> (String, [String]) {
        switch provider {
        case .claudeCode:
            var args = ["--output-format", "stream-json"]
            if let claudeId = claudeSessionId {
                // Resume the prior conversation
                args += ["-c", claudeId]
            }
            return ("/usr/local/bin/claude", args)

        case .codex:
            return ("/usr/local/bin/codex", ["--json"])

        case .opencode:
            return ("/usr/local/bin/opencode", ["run"])

        case .antigravity:
            return ("/usr/local/bin/antigravity", ["run"])

        case .hermes:
            return ("/usr/local/bin/hermes", [])
        }
    }

    // MARK: - Private: stdout processing

    /// Process raw stdout data: split on newlines and normalize each line.
    private func processOutput(_ data: Data) {
        // Buffer splitting on newline — handles partial lines by accumulating.
        // For simplicity: each `availableData` call typically ends on a newline boundary
        // when the child writes complete lines. We split defensively here.
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for lineData in lines {
            guard !lineData.isEmpty else { continue }
            if let event = normalizer.normalize(streamLine: Data(lineData)) {
                // Capture claudeSessionId from SessionStart for future --continue
                if case .sessionStart(let id, _, _, _, _) = event {
                    lock.lock()
                    claudeSessionId = id
                    lock.unlock()
                }
                onAgentEvent?(event)
            }
        }
    }
}
