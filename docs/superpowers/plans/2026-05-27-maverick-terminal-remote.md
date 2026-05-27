# Maverick Terminal Remote — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar daemon (`server/`) and iOS app (`client/`) that create and control persistent pty sessions over Tailscale via WebSocket, with a shared Swift package for message types.

**Architecture:** Mac daemon manages pty sessions via `forkpty`, exposes them over `NWListener` WebSocket on port 8765; iOS app connects over Tailscale using `URLSessionWebSocketTask` and renders output with SwiftTerm; shared `MaverickProtocol` Swift package defines all message types used by both.

**Tech Stack:** Swift 5.9+, SwiftUI, Network.framework (server), SwiftTerm via SPM (client), URLSessionWebSocketTask (client), XCTest, xcodegen

---

## Directory Layout

```
maverick-app/
  project.yml                         ← xcodegen spec
  shared/                             ← MaverickProtocol Swift package
    Package.swift
    Sources/MaverickProtocol/
      Messages.swift                  ← Codable client/server message enums
      SessionInfo.swift               ← SessionInfo struct
    Tests/MaverickProtocolTests/
      MessagesTests.swift
  server/                             ← MaverickAgent macOS menu bar app
    Sources/
      AppDelegate.swift
      MenuBarController.swift
      CircularBuffer.swift
      PTYSession.swift
      SessionManager.swift
      ClientHandler.swift
      WebSocketServer.swift
    Tests/
      CircularBufferTests.swift
      SessionManagerTests.swift
      WebSocketIntegrationTests.swift
    Info.plist
  client/                             ← MaverickRemote iOS app
    Sources/
      App/
        MaverickRemoteApp.swift
        ContentView.swift
      Features/
        Connection/
          ConnectionManager.swift
          ConnectionView.swift
        Sessions/
          SessionStore.swift
          SessionListView.swift
        Terminal/
          TerminalViewController.swift
          TerminalContainerView.swift
          InputToolbar.swift
    Tests/
      ConnectionManagerTests.swift
      SessionStoreTests.swift
    Info.plist
```

---

## Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `shared/Package.swift`
- Create: `server/Info.plist`
- Create: `client/Info.plist`

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p shared/Sources/MaverickProtocol
mkdir -p shared/Tests/MaverickProtocolTests
mkdir -p server/Sources server/Tests
mkdir -p client/Sources/App
mkdir -p client/Sources/Features/Connection
mkdir -p client/Sources/Features/Sessions
mkdir -p client/Sources/Features/Terminal
mkdir -p client/Tests
```

- [ ] **Step 3: Write `shared/Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaverickProtocol",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MaverickProtocol", targets: ["MaverickProtocol"])
    ],
    targets: [
        .target(name: "MaverickProtocol"),
        .testTarget(name: "MaverickProtocolTests", dependencies: ["MaverickProtocol"])
    ]
)
```

- [ ] **Step 4: Write `server/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIdentifier</key>
    <string>com.malhar.MaverickAgent</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
```

- [ ] **Step 5: Write `client/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.malhar.MaverickRemote</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>UILaunchScreen</key>
    <dict/>
</dict>
</plist>
```

- [ ] **Step 6: Write `project.yml`**

```yaml
name: Maverick
options:
  bundleIdPrefix: com.malhar
  deploymentTarget:
    macOS: "13.0"
    iOS: "17.0"
  createIntermediateGroups: true

packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.2.0"
  MaverickProtocol:
    path: shared

targets:
  MaverickAgent:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources: server/Sources
    dependencies:
      - package: MaverickProtocol
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.malhar.MaverickAgent
      INFOPLIST_FILE: server/Info.plist

  MaverickAgentTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "13.0"
    sources: server/Tests
    dependencies:
      - target: MaverickAgent
      - package: MaverickProtocol

  MaverickRemote:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources: client/Sources
    dependencies:
      - package: SwiftTerm
      - package: MaverickProtocol
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.malhar.MaverickRemote
      INFOPLIST_FILE: client/Info.plist

  MaverickRemoteTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources: client/Tests
    dependencies:
      - target: MaverickRemote
      - package: MaverickProtocol

schemes:
  MaverickAgent:
    build:
      targets:
        MaverickAgent: all
    test:
      targets: [MaverickAgentTests]
  MaverickRemote:
    build:
      targets:
        MaverickRemote: all
    test:
      targets: [MaverickRemoteTests]
```

- [ ] **Step 7: Generate Xcode project**

```bash
xcodegen generate
```

Expected: `Maverick.xcodeproj` created with both targets and resolved SPM packages.

- [ ] **Step 8: Commit**

```bash
git init
git add .
git commit -m "feat: scaffold Maverick workspace with xcodegen"
```

---

## Task 2: Shared Protocol Types

**Files:**
- Create: `shared/Sources/MaverickProtocol/SessionInfo.swift`
- Create: `shared/Sources/MaverickProtocol/Messages.swift`
- Create: `shared/Tests/MaverickProtocolTests/MessagesTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// shared/Tests/MaverickProtocolTests/MessagesTests.swift
import XCTest
@testable import MaverickProtocol

final class MessagesTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testSessionInfoRoundtrip() throws {
        let info = SessionInfo(id: UUID(), name: "test", shell: "/bin/zsh", createdAt: Date())
        let data = try encoder.encode(info)
        let decoded = try decoder.decode(SessionInfo.self, from: data)
        XCTAssertEqual(decoded.id, info.id)
        XCTAssertEqual(decoded.name, info.name)
        XCTAssertEqual(decoded.shell, info.shell)
    }

    func testClientMessageCreateSessionRoundtrip() throws {
        let msg = ClientMessage.createSession(name: "claude", shell: "/bin/zsh")
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ClientMessage.self, from: data)
        guard case .createSession(let name, let shell) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(name, "claude")
        XCTAssertEqual(shell, "/bin/zsh")
    }

    func testServerMessageOutputRoundtrip() throws {
        let id = UUID()
        let msg = ServerMessage.output(sessionId: id, data: "aGVsbG8=")
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ServerMessage.self, from: data)
        guard case .output(let sid, let b64) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(sid, id)
        XCTAssertEqual(b64, "aGVsbG8=")
    }

    func testMalformedJSONThrows() {
        let bad = Data("{\"type\":\"unknown_type\"}".utf8)
        XCTAssertThrowsError(try decoder.decode(ClientMessage.self, from: bad))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shared && swift test 2>&1 | tail -20
```

Expected: compile error — `SessionInfo`, `ClientMessage`, `ServerMessage` not defined.

- [ ] **Step 3: Write `SessionInfo.swift`**

```swift
// shared/Sources/MaverickProtocol/SessionInfo.swift
import Foundation

public struct SessionInfo: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let shell: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, shell: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.shell = shell
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Write `Messages.swift`**

```swift
// shared/Sources/MaverickProtocol/Messages.swift
import Foundation

private enum MessageType: String, Codable {
    case listSessions = "list_sessions"
    case createSession = "create_session"
    case attachSession = "attach_session"
    case input, resize
    case closeSession = "close_session"
    case sessionList = "session_list"
    case sessionCreated = "session_created"
    case output, scrollback
    case sessionClosed = "session_closed"
    case error
}

public enum ClientMessage: Codable, Sendable {
    case listSessions
    case createSession(name: String, shell: String)
    case attachSession(sessionId: UUID)
    case input(sessionId: UUID, data: String)
    case resize(sessionId: UUID, cols: Int, rows: Int)
    case closeSession(sessionId: UUID)

    private enum CK: String, CodingKey { case type, name, shell, sessionId, data, cols, rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(MessageType.self, forKey: .type) {
        case .listSessions:  self = .listSessions
        case .createSession: self = .createSession(name: try c.decode(String.self, forKey: .name), shell: try c.decode(String.self, forKey: .shell))
        case .attachSession: self = .attachSession(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        case .input:         self = .input(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .resize:        self = .resize(sessionId: try c.decode(UUID.self, forKey: .sessionId), cols: try c.decode(Int.self, forKey: .cols), rows: try c.decode(Int.self, forKey: .rows))
        case .closeSession:  self = .closeSession(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unexpected client message type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .listSessions:
            try c.encode(MessageType.listSessions, forKey: .type)
        case .createSession(let n, let s):
            try c.encode(MessageType.createSession, forKey: .type); try c.encode(n, forKey: .name); try c.encode(s, forKey: .shell)
        case .attachSession(let id):
            try c.encode(MessageType.attachSession, forKey: .type); try c.encode(id, forKey: .sessionId)
        case .input(let id, let d):
            try c.encode(MessageType.input, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .resize(let id, let cols, let rows):
            try c.encode(MessageType.resize, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(cols, forKey: .cols); try c.encode(rows, forKey: .rows)
        case .closeSession(let id):
            try c.encode(MessageType.closeSession, forKey: .type); try c.encode(id, forKey: .sessionId)
        }
    }
}

public enum ServerMessage: Codable, Sendable {
    case sessionList(sessions: [SessionInfo])
    case sessionCreated(session: SessionInfo)
    case output(sessionId: UUID, data: String)
    case scrollback(sessionId: UUID, data: String)
    case sessionClosed(sessionId: UUID)
    case error(message: String)

    private enum CK: String, CodingKey { case type, sessions, session, sessionId, data, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(MessageType.self, forKey: .type) {
        case .sessionList:    self = .sessionList(sessions: try c.decode([SessionInfo].self, forKey: .sessions))
        case .sessionCreated: self = .sessionCreated(session: try c.decode(SessionInfo.self, forKey: .session))
        case .output:         self = .output(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .scrollback:     self = .scrollback(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .sessionClosed:  self = .sessionClosed(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        case .error:          self = .error(message: try c.decode(String.self, forKey: .message))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unexpected server message type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .sessionList(let s):
            try c.encode(MessageType.sessionList, forKey: .type); try c.encode(s, forKey: .sessions)
        case .sessionCreated(let s):
            try c.encode(MessageType.sessionCreated, forKey: .type); try c.encode(s, forKey: .session)
        case .output(let id, let d):
            try c.encode(MessageType.output, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .scrollback(let id, let d):
            try c.encode(MessageType.scrollback, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .sessionClosed(let id):
            try c.encode(MessageType.sessionClosed, forKey: .type); try c.encode(id, forKey: .sessionId)
        case .error(let m):
            try c.encode(MessageType.error, forKey: .type); try c.encode(m, forKey: .message)
        }
    }
}
```

- [ ] **Step 5: Run tests**

```bash
cd shared && swift test
```

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add shared/
git commit -m "feat: add MaverickProtocol shared message types"
```

---

## Task 3: CircularBuffer (Scrollback Ring Buffer)

**Files:**
- Create: `server/Sources/CircularBuffer.swift`
- Create: `server/Tests/CircularBufferTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// server/Tests/CircularBufferTests.swift
import XCTest
@testable import MaverickAgent

final class CircularBufferTests: XCTestCase {
    func testAppendAndRetrieve() {
        var buf = CircularBuffer<Int>(capacity: 4)
        buf.append(1); buf.append(2); buf.append(3)
        XCTAssertEqual(buf.contents, [1, 2, 3])
    }

    func testOverflowEvictsOldest() {
        var buf = CircularBuffer<Int>(capacity: 3)
        buf.append(1); buf.append(2); buf.append(3); buf.append(4)
        XCTAssertEqual(buf.contents, [2, 3, 4])
    }

    func testAppendContentsOf() {
        var buf = CircularBuffer<Int>(capacity: 3)
        buf.append(contentsOf: [1, 2, 3, 4, 5])
        XCTAssertEqual(buf.contents, [3, 4, 5])
    }

    func testEmptyBuffer() {
        let buf = CircularBuffer<Int>(capacity: 4)
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(buf.contents, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

Expected: compile error — `CircularBuffer` not defined.

- [ ] **Step 3: Write `server/Sources/CircularBuffer.swift`**

```swift
// server/Sources/CircularBuffer.swift
struct CircularBuffer<T> {
    private var storage: [T?]
    private var head = 0
    private var count = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: T) {
        let index = (head + count) % capacity
        storage[index] = element
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    mutating func append(contentsOf elements: some Sequence<T>) {
        for e in elements { append(e) }
    }

    var contents: [T] {
        (0..<count).compactMap { storage[(head + $0) % capacity] }
    }

    var isEmpty: Bool { count == 0 }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "Test.*passed|FAILED"
```

Expected: All 4 `CircularBufferTests` pass.

- [ ] **Step 5: Commit**

```bash
git add server/
git commit -m "feat: add CircularBuffer for scrollback ring buffer"
```

---

## Task 4: PTYSession

**Files:**
- Create: `server/Sources/PTYSession.swift`

- [ ] **Step 1: Write `server/Sources/PTYSession.swift`**

No unit test here — `forkpty` requires a real process. Integration coverage comes in Task 8.

```swift
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

    init(name: String, shell: String = "/bin/zsh") {
        self.info = SessionInfo(name: name, shell: shell)
    }

    func start() throws {
        var ws = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0
        childPid = forkpty(&master, nil, nil, &ws)
        guard childPid >= 0 else { throw PTYError.forkFailed(errno) }

        if childPid == 0 {
            let shell = info.shell
            execl(shell, shell, "-l", nil as UnsafePointer<CChar>?)
            exit(1)
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
        return Data(scrollback.contents)
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
        if childPid > 0 { kill(childPid, SIGTERM) }
        source?.cancel()
    }

    private func closeFd() {
        if masterFd >= 0 { close(masterFd); masterFd = -1 }
    }

    enum PTYError: Error { case forkFailed(Int32) }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add server/Sources/PTYSession.swift
git commit -m "feat: add PTYSession with forkpty, scrollback, and output observers"
```

---

## Task 5: SessionManager

**Files:**
- Create: `server/Sources/SessionManager.swift`
- Create: `server/Tests/SessionManagerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// server/Tests/SessionManagerTests.swift
import XCTest
@testable import MaverickAgent

final class SessionManagerTests: XCTestCase {
    func testCreateAndListSession() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "test", shell: "/bin/sh")
        let list = await mgr.listSessions()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, info.id)
        XCTAssertEqual(list[0].name, "test")
        await mgr.closeSession(id: info.id)
    }

    func testCloseSessionRemovesIt() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "bye", shell: "/bin/sh")
        await mgr.closeSession(id: info.id)
        let list = await mgr.listSessions()
        XCTAssertTrue(list.isEmpty)
    }

    func testScrollbackEmptyOnNewSession() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "s", shell: "/bin/sh")
        // Give shell a moment to emit prompt, then read scrollback
        try await Task.sleep(for: .milliseconds(200))
        let sb = await mgr.getScrollback(sessionId: info.id)
        XCTAssertNotNil(sb)
        await mgr.closeSession(id: info.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|FAILED" | head -10
```

Expected: compile error — `SessionManager` not defined.

- [ ] **Step 3: Write `server/Sources/SessionManager.swift`**

```swift
// server/Sources/SessionManager.swift
import Foundation
import MaverickProtocol

actor SessionManager {
    private var sessions: [UUID: PTYSession] = [:]
    var onSessionClosed: ((UUID) -> Void)?

    func createSession(name: String, shell: String = "/bin/zsh") throws -> SessionInfo {
        let session = PTYSession(name: name, shell: shell)
        session.onExit = { [weak self, id = session.info.id] in
            Task { await self?.handleExit(id: id) }
        }
        try session.start()
        sessions[session.info.id] = session
        return session.info
    }

    func listSessions() -> [SessionInfo] {
        sessions.values.map(\.info).sorted { $0.createdAt < $1.createdAt }
    }

    func getScrollback(sessionId: UUID) -> Data? {
        sessions[sessionId]?.getScrollback()
    }

    func write(sessionId: UUID, data: Data) {
        sessions[sessionId]?.write(data)
    }

    func resize(sessionId: UUID, cols: UInt16, rows: UInt16) {
        sessions[sessionId]?.resize(cols: cols, rows: rows)
    }

    func addOutputObserver(sessionId: UUID, clientId: UUID, handler: @escaping (Data) -> Void) {
        sessions[sessionId]?.addObserver(id: clientId, handler: handler)
    }

    func removeOutputObserver(sessionId: UUID, clientId: UUID) {
        sessions[sessionId]?.removeObserver(id: clientId)
    }

    func closeSession(id: UUID) {
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }

    private func handleExit(id: UUID) {
        sessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "Test.*passed|FAILED"
```

Expected: All 3 `SessionManagerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add server/Sources/SessionManager.swift server/Tests/SessionManagerTests.swift
git commit -m "feat: add SessionManager actor with session lifecycle"
```

---

## Task 6: ClientHandler

**Files:**
- Create: `server/Sources/ClientHandler.swift`

- [ ] **Step 1: Write `server/Sources/ClientHandler.swift`**

```swift
// server/Sources/ClientHandler.swift
import Foundation
import Network
import MaverickProtocol

final class ClientHandler: @unchecked Sendable {
    let id: UUID
    private let connection: NWConnection
    private let sessionManager: SessionManager
    private var attachedSessionId: UUID?
    let onDisconnect: () -> Void

    init(id: UUID, connection: NWConnection, sessionManager: SessionManager, onDisconnect: @escaping () -> Void) {
        self.id = id
        self.connection = connection
        self.sessionManager = sessionManager
        self.onDisconnect = onDisconnect
    }

    func start() {
        connection.start(queue: .global())
        receive()
    }

    func disconnect() {
        if let sid = attachedSessionId {
            Task { await sessionManager.removeOutputObserver(sessionId: sid, clientId: id) }
        }
        connection.cancel()
    }

    private func receive() {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if error != nil { self.handleDisconnect(); return }
            if let content, let msg = try? JSONDecoder().decode(ClientMessage.self, from: content) {
                Task { await self.handle(msg) }
            }
            self.receive()
        }
    }

    private func handle(_ message: ClientMessage) async {
        switch message {
        case .listSessions:
            send(.sessionList(sessions: await sessionManager.listSessions()))

        case .createSession(let name, let shell):
            do {
                let info = try await sessionManager.createSession(name: name, shell: shell)
                send(.sessionCreated(session: info))
                send(.sessionList(sessions: await sessionManager.listSessions()))
                await attach(sessionId: info.id)
            } catch {
                send(.error(message: error.localizedDescription))
            }

        case .attachSession(let sessionId):
            await attach(sessionId: sessionId)

        case .input(let sessionId, let data):
            if let bytes = Data(base64Encoded: data) {
                await sessionManager.write(sessionId: sessionId, data: bytes)
            }

        case .resize(let sessionId, let cols, let rows):
            await sessionManager.resize(sessionId: sessionId, cols: UInt16(cols), rows: UInt16(rows))

        case .closeSession(let sessionId):
            await sessionManager.closeSession(id: sessionId)
        }
    }

    private func attach(sessionId: UUID) async {
        if let prev = attachedSessionId {
            await sessionManager.removeOutputObserver(sessionId: prev, clientId: id)
        }
        attachedSessionId = sessionId
        if let sb = await sessionManager.getScrollback(sessionId: sessionId), !sb.isEmpty {
            send(.scrollback(sessionId: sessionId, data: sb.base64EncodedString()))
        }
        let cid = id
        await sessionManager.addOutputObserver(sessionId: sessionId, clientId: cid) { [weak self] data in
            self?.send(.output(sessionId: sessionId, data: data.base64EncodedString()))
        }
    }

    func send(_ message: ServerMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
        connection.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    private func handleDisconnect() {
        if let sid = attachedSessionId {
            Task { await sessionManager.removeOutputObserver(sessionId: sid, clientId: id) }
        }
        onDisconnect()
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add server/Sources/ClientHandler.swift
git commit -m "feat: add ClientHandler for per-connection WebSocket message routing"
```

---

## Task 7: WebSocketServer

**Files:**
- Create: `server/Sources/WebSocketServer.swift`
- Create: `server/Tests/WebSocketIntegrationTests.swift`

- [ ] **Step 1: Write failing integration test**

```swift
// server/Tests/WebSocketIntegrationTests.swift
import XCTest
import Foundation
@testable import MaverickAgent
import MaverickProtocol

final class WebSocketIntegrationTests: XCTestCase {
    func testConnectListAndCreateSession() async throws {
        let mgr = SessionManager()
        let server = WebSocketServer(sessionManager: mgr, port: 0) // port 0 = ephemeral
        try server.start()
        let port = try XCTUnwrap(server.actualPort)

        let url = URL(string: "ws://127.0.0.1:\(port)/ws")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Send list_sessions
        let listMsg = try JSONEncoder().encode(ClientMessage.listSessions)
        try await task.send(.string(String(data: listMsg, encoding: .utf8)!))

        // Receive session_list
        let response = try await task.receive()
        guard case .string(let text) = response,
              let data = text.data(using: .utf8),
              case .sessionList(let sessions) = try JSONDecoder().decode(ServerMessage.self, from: data)
        else { return XCTFail("expected session_list") }
        XCTAssertTrue(sessions.isEmpty)

        task.cancel()
        server.stop()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|FAILED" | head -10
```

Expected: compile error — `WebSocketServer` not defined.

- [ ] **Step 3: Write `server/Sources/WebSocketServer.swift`**

```swift
// server/Sources/WebSocketServer.swift
import Foundation
import Network
import MaverickProtocol

final class WebSocketServer {
    private var listener: NWListener?
    private var clients: [UUID: ClientHandler] = [:]
    private let sessionManager: SessionManager
    private let port: UInt16

    var actualPort: UInt16? { listener?.port?.rawValue }

    init(sessionManager: SessionManager, port: UInt16 = 8765) {
        self.sessionManager = sessionManager
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        let wsOpts = NWProtocolWebSocket.Options()
        wsOpts.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)

        let nwPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener?.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("[MaverickAgent] listener failed: \(err)")
            }
        }
        listener?.start(queue: .global())

        // Give listener a moment to bind
        Thread.sleep(forTimeInterval: 0.1)

        Task {
            await self.sessionManager.setClosedHandler { [weak self] id in
                self?.broadcastSessionClosed(id: id)
            }
        }
    }

    func stop() {
        listener?.cancel()
        clients.values.forEach { $0.disconnect() }
        clients.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let handler = ClientHandler(
            id: id,
            connection: connection,
            sessionManager: sessionManager,
            onDisconnect: { [weak self] in self?.clients.removeValue(forKey: id) }
        )
        clients[id] = handler
        handler.start()
    }

    private func broadcastSessionClosed(_ sessionId: UUID) {
        clients.values.forEach { $0.send(.sessionClosed(sessionId: sessionId)) }
    }
}
```

- [ ] **Step 4: Add `setClosedHandler` to SessionManager**

Add to `server/Sources/SessionManager.swift` inside the `actor SessionManager` body:

```swift
func setClosedHandler(_ handler: @escaping (UUID) -> Void) {
    onSessionClosed = handler
}
```

- [ ] **Step 5: Run integration test**

```bash
xcodebuild test -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "Test.*passed|FAILED"
```

Expected: `WebSocketIntegrationTests.testConnectListAndCreateSession` passes.

- [ ] **Step 6: Commit**

```bash
git add server/
git commit -m "feat: add WebSocketServer with NWListener and integration test"
```

---

## Task 8: Mac Menu Bar App Shell

**Files:**
- Create: `server/Sources/AppDelegate.swift`
- Create: `server/Sources/MenuBarController.swift`

- [ ] **Step 1: Write `server/Sources/AppDelegate.swift`**

```swift
// server/Sources/AppDelegate.swift
import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        menuBar?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.stop()
    }
}
```

- [ ] **Step 2: Write `server/Sources/MenuBarController.swift`**

```swift
// server/Sources/MenuBarController.swift
import Cocoa
import MaverickProtocol

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var sessionManager = SessionManager()
    private var server: WebSocketServer?
    private var connectedCount = 0

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Maverick")
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        server = WebSocketServer(sessionManager: sessionManager, port: 8765)
        do {
            try server?.start()
            updateTitle(connected: 0)
        } catch {
            statusItem?.button?.title = "⚠ Maverick"
        }
    }

    func stop() {
        server?.stop()
    }

    @objc private func togglePopover() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Maverick Agent — running on :8765", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.popUpMenu(menu)
    }

    private func updateTitle(connected: Int) {
        let label = connected > 0 ? " \(connected)" : ""
        statusItem?.button?.title = label
    }
}
```

- [ ] **Step 3: Build the server target**

```bash
xcodebuild build -scheme MaverickAgent -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add server/Sources/AppDelegate.swift server/Sources/MenuBarController.swift
git commit -m "feat: add macOS menu bar app shell with WebSocket server startup"
```

---

## Task 9: iOS ConnectionManager

**Files:**
- Create: `client/Sources/Features/Connection/ConnectionManager.swift`
- Create: `client/Tests/ConnectionManagerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// client/Tests/ConnectionManagerTests.swift
import XCTest
@testable import MaverickRemote
import MaverickProtocol

final class ConnectionManagerTests: XCTestCase {
    func testInitialStateIsDisconnected() {
        let mgr = ConnectionManager()
        XCTAssertEqual(mgr.state, .disconnected)
    }

    func testReconnectDelayDoublesUpToMax() {
        let mgr = ConnectionManager()
        XCTAssertEqual(mgr.nextDelay(), 1.0)
        mgr.recordFailure()
        XCTAssertEqual(mgr.nextDelay(), 2.0)
        mgr.recordFailure()
        XCTAssertEqual(mgr.nextDelay(), 4.0)
        // Saturate
        for _ in 0..<10 { mgr.recordFailure() }
        XCTAssertEqual(mgr.nextDelay(), 30.0)
    }

    func testResetDelayClearsBackoff() {
        let mgr = ConnectionManager()
        mgr.recordFailure(); mgr.recordFailure()
        mgr.resetDelay()
        XCTAssertEqual(mgr.nextDelay(), 1.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "error:|FAILED" | head -10
```

Expected: compile error — `ConnectionManager` not defined.

- [ ] **Step 3: Write `client/Sources/Features/Connection/ConnectionManager.swift`**

```swift
// client/Sources/Features/Connection/ConnectionManager.swift
import Foundation
import MaverickProtocol

@Observable
final class ConnectionManager {
    enum State: Equatable { case disconnected, connecting, connected }

    var state: State = .disconnected
    var lastError: String?
    var onMessage: ((ServerMessage) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var host = ""
    private var port = 8765
    private var token = ""
    private(set) var delay: TimeInterval = 1

    // MARK: - Public

    func connect(host: String, port: Int = 8765, token: String = "") {
        self.host = host; self.port = port; self.token = token
        UserDefaults.standard.set(host, forKey: "lastHost")
        UserDefaults.standard.set(port, forKey: "lastPort")
        openSocket()
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        state = .disconnected
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    // MARK: - Backoff helpers (internal for tests)

    func nextDelay() -> TimeInterval { delay }
    func recordFailure() { delay = min(delay * 2, 30) }
    func resetDelay() { delay = 1 }

    // MARK: - Private

    private func openSocket() {
        state = .connecting
        let urlStr = token.isEmpty
            ? "ws://\(host):\(port)/ws"
            : "ws://\(host):\(port)/ws?token=\(token)"
        guard let url = URL(string: urlStr) else { state = .disconnected; return }
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        readLoop()
    }

    private func readLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                self.state = .connected
                self.resetDelay()
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let serverMsg = try? JSONDecoder().decode(ServerMessage.self, from: data) {
                    DispatchQueue.main.async { self.onMessage?(serverMsg) }
                }
                self.readLoop()
            case .failure(let err):
                self.lastError = err.localizedDescription
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        state = .disconnected
        let d = delay
        recordFailure()
        let item = DispatchWorkItem { [weak self] in self?.openSocket() }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: item)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "Test.*passed|FAILED"
```

Expected: All 3 `ConnectionManagerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add client/
git commit -m "feat: add ConnectionManager with exponential backoff reconnect"
```

---

## Task 10: SessionStore

**Files:**
- Create: `client/Sources/Features/Sessions/SessionStore.swift`
- Create: `client/Tests/SessionStoreTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// client/Tests/SessionStoreTests.swift
import XCTest
@testable import MaverickRemote
import MaverickProtocol

final class SessionStoreTests: XCTestCase {
    func testSessionListMessagePopulatesStore() {
        let store = SessionStore()
        let sessions = [
            SessionInfo(name: "claude", shell: "/bin/zsh"),
            SessionInfo(name: "bash", shell: "/bin/bash")
        ]
        store.handle(.sessionList(sessions: sessions))
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions[0].name, "claude")
    }

    func testSessionCreatedAppendsIfNotPresent() {
        let store = SessionStore()
        let info = SessionInfo(name: "new", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].id, info.id)
    }

    func testSessionClosedRemovesEntry() {
        let store = SessionStore()
        let info = SessionInfo(name: "bye", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        store.handle(.sessionClosed(sessionId: info.id))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testActiveSessionClearedWhenClosed() {
        let store = SessionStore()
        let info = SessionInfo(name: "active", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        store.activeSessionId = info.id
        store.handle(.sessionClosed(sessionId: info.id))
        XCTAssertNil(store.activeSessionId)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "error:|FAILED" | head -10
```

Expected: compile error — `SessionStore` not defined.

- [ ] **Step 3: Write `client/Sources/Features/Sessions/SessionStore.swift`**

```swift
// client/Sources/Features/Sessions/SessionStore.swift
import Foundation
import MaverickProtocol

@Observable
final class SessionStore {
    var sessions: [SessionInfo] = []
    var activeSessionId: UUID?
    var outputHandlers: [UUID: (Data) -> Void] = [:]

    func handle(_ message: ServerMessage) {
        switch message {
        case .sessionList(let list):
            sessions = list
        case .sessionCreated(let info):
            if !sessions.contains(where: { $0.id == info.id }) {
                sessions.append(info)
            }
        case .sessionClosed(let id):
            sessions.removeAll { $0.id == id }
            if activeSessionId == id { activeSessionId = nil }
            outputHandlers.removeValue(forKey: id)
        case .output(let id, let b64):
            if let data = Data(base64Encoded: b64) {
                outputHandlers[id]?(data)
            }
        case .scrollback(let id, let b64):
            if let data = Data(base64Encoded: b64) {
                outputHandlers[id]?(data)
            }
        case .error(let msg):
            print("[SessionStore] server error: \(msg)")
        }
    }

    func registerOutputHandler(sessionId: UUID, handler: @escaping (Data) -> Void) {
        outputHandlers[sessionId] = handler
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "Test.*passed|FAILED"
```

Expected: All 4 `SessionStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add client/
git commit -m "feat: add SessionStore with message routing and output handler registry"
```

---

## Task 11: TerminalViewController + TerminalContainerView

**Files:**
- Create: `client/Sources/Features/Terminal/TerminalViewController.swift`
- Create: `client/Sources/Features/Terminal/TerminalContainerView.swift`
- Create: `client/Sources/Features/Terminal/InputToolbar.swift`

- [ ] **Step 1: Write `client/Sources/Features/Terminal/TerminalViewController.swift`**

```swift
// client/Sources/Features/Terminal/TerminalViewController.swift
import UIKit
import SwiftTerm

final class TerminalViewController: UIViewController {
    private(set) var terminal: TerminalView!
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        terminal = TerminalView(frame: view.bounds)
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminal.terminalDelegate = self
        terminal.backgroundColor = .black
        view.addSubview(terminal)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let cols = terminal.getTerminal().cols
        let rows = terminal.getTerminal().rows
        onResize?(cols, rows)
    }

    func feed(data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(byteArray: Array(data))
        }
    }

    func sendCtrlC() {
        onInput?(Data([0x03]))
    }

    func sendEsc() {
        onInput?(Data([0x1B]))
    }

    func sendTab() {
        onInput?(Data([0x09]))
    }

    func sendArrow(_ code: String) {
        if let d = "\u{1B}\(code)".data(using: .utf8) { onInput?(d) }
    }
}

extension TerminalViewController: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onResize?(newCols, newRows)
    }
    func bell(source: TerminalView) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
```

- [ ] **Step 2: Write `client/Sources/Features/Terminal/TerminalContainerView.swift`**

```swift
// client/Sources/Features/Terminal/TerminalContainerView.swift
import SwiftUI

struct TerminalContainerView: UIViewControllerRepresentable {
    let sessionId: UUID
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection

    func makeUIViewController(context: Context) -> TerminalViewController {
        let vc = TerminalViewController()
        vc.onInput = { data in
            let b64 = data.base64EncodedString()
            connection.send(.input(sessionId: sessionId, data: b64))
        }
        vc.onResize = { cols, rows in
            connection.send(.resize(sessionId: sessionId, cols: cols, rows: rows))
        }
        store.registerOutputHandler(sessionId: sessionId) { data in
            vc.feed(data: data)
        }
        connection.send(.attachSession(sessionId: sessionId))
        return vc
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {}
}
```

- [ ] **Step 3: Write `client/Sources/Features/Terminal/InputToolbar.swift`**

```swift
// client/Sources/Features/Terminal/InputToolbar.swift
import SwiftUI

struct InputToolbar: View {
    let terminalVC: TerminalViewController
    @State private var ctrlLatched = false

    var body: some View {
        HStack(spacing: 4) {
            Button("Ctrl") {
                ctrlLatched.toggle()
            }
            .foregroundStyle(ctrlLatched ? .yellow : .primary)
            .buttonStyle(.bordered)

            Button("Esc")  { terminalVC.sendEsc();  ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("Tab")  { terminalVC.sendTab();  ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("↑")  { terminalVC.sendArrow("[A]"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("↓")  { terminalVC.sendArrow("[B]"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("←")  { terminalVC.sendArrow("[D]"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("→")  { terminalVC.sendArrow("[C]"); ctrlLatched = false }
                .buttonStyle(.bordered)
            Button("^C") { terminalVC.sendCtrlC(); ctrlLatched = false }
                .foregroundStyle(.red)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add client/Sources/Features/Terminal/
git commit -m "feat: add TerminalViewController, TerminalContainerView, and InputToolbar"
```

---

## Task 12: iOS UI — ConnectionView, SessionListView, ContentView

**Files:**
- Create: `client/Sources/Features/Connection/ConnectionView.swift`
- Create: `client/Sources/Features/Sessions/SessionListView.swift`
- Create: `client/Sources/App/ContentView.swift`
- Create: `client/Sources/App/MaverickRemoteApp.swift`

- [ ] **Step 1: Write `client/Sources/Features/Connection/ConnectionView.swift`**

```swift
// client/Sources/Features/Connection/ConnectionView.swift
import SwiftUI

struct ConnectionView: View {
    @Environment(ConnectionManager.self) var connection
    @State private var host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
    @State private var port = UserDefaults.standard.integer(forKey: "lastPort") == 0
        ? "8765"
        : String(UserDefaults.standard.integer(forKey: "lastPort"))
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Address (Tailscale)") {
                    TextField("hostname or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("Auth (optional)") {
                    SecureField("Token", text: $token)
                }
                Section {
                    Button("Connect") {
                        connection.connect(
                            host: host,
                            port: Int(port) ?? 8765,
                            token: token
                        )
                    }
                    .disabled(host.isEmpty || connection.state == .connecting)
                    if connection.state == .connecting {
                        HStack { Spacer(); ProgressView("Connecting…"); Spacer() }
                    }
                    if let err = connection.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Maverick")
        }
    }
}
```

- [ ] **Step 2: Write `client/Sources/Features/Sessions/SessionListView.swift`**

```swift
// client/Sources/Features/Sessions/SessionListView.swift
import SwiftUI
import MaverickProtocol

struct SessionListView: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @State private var showNewSession = false
    @State private var newName = ""

    var body: some View {
        List(store.sessions, selection: Binding(
            get: { store.activeSessionId },
            set: { store.activeSessionId = $0 }
        )) { session in
            Label(session.name, systemImage: "terminal")
                .tag(session.id)
                .swipeActions(edge: .trailing) {
                    Button("Close", role: .destructive) {
                        connection.send(.closeSession(sessionId: session.id))
                    }
                }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("", systemImage: "plus") { showNewSession = true }
            }
        }
        .alert("New Session", isPresented: $showNewSession) {
            TextField("Name", text: $newName)
            Button("Create") {
                guard !newName.isEmpty else { return }
                connection.send(.createSession(name: newName, shell: "/bin/zsh"))
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .onAppear {
            connection.send(.listSessions)
        }
    }
}
```

- [ ] **Step 3: Write `client/Sources/App/ContentView.swift`**

```swift
// client/Sources/App/ContentView.swift
import SwiftUI

// Wrapper that owns the TerminalViewController so InputToolbar can reference it.
struct TerminalWithToolbarView: View {
    let sessionId: UUID
    @State private var terminalVC = TerminalViewController()
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection

    var body: some View {
        VStack(spacing: 0) {
            TerminalContainerView(sessionId: sessionId, terminalVC: terminalVC)
                .ignoresSafeArea(.keyboard)
            InputToolbar(terminalVC: terminalVC)
        }
    }
}

struct ContentView: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionStore.self) var store

    var body: some View {
        if connection.state == .connected {
            NavigationSplitView {
                SessionListView()
            } detail: {
                if let id = store.activeSessionId {
                    TerminalWithToolbarView(sessionId: id)
                } else {
                    ContentUnavailableView("No Session", systemImage: "terminal", description: Text("Tap + to create a session"))
                }
            }
        } else {
            ConnectionView()
        }
    }
}
```

Also update `TerminalContainerView` to accept an externally-created `TerminalViewController` instead of creating one internally — replace the `makeUIViewController` signature:

```swift
// client/Sources/Features/Terminal/TerminalContainerView.swift
import SwiftUI

struct TerminalContainerView: UIViewControllerRepresentable {
    let sessionId: UUID
    let terminalVC: TerminalViewController          // injected from TerminalWithToolbarView
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection

    func makeUIViewController(context: Context) -> TerminalViewController {
        terminalVC.onInput = { data in
            connection.send(.input(sessionId: sessionId, data: data.base64EncodedString()))
        }
        terminalVC.onResize = { cols, rows in
            connection.send(.resize(sessionId: sessionId, cols: cols, rows: rows))
        }
        store.registerOutputHandler(sessionId: sessionId) { data in
            terminalVC.feed(data: data)
        }
        connection.send(.attachSession(sessionId: sessionId))
        return terminalVC
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {}
}
```

- [ ] **Step 4: Write `client/Sources/App/MaverickRemoteApp.swift`**

```swift
// client/Sources/App/MaverickRemoteApp.swift
import SwiftUI

@main
struct MaverickRemoteApp: App {
    @State private var connection = ConnectionManager()
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
                .environment(store)
                .task {
                    // Wire output routing after @State is initialized by SwiftUI
                    connection.onMessage = { [weak store] msg in
                        store?.handle(msg)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    let host = UserDefaults.standard.string(forKey: "lastHost") ?? ""
                    let port = UserDefaults.standard.integer(forKey: "lastPort")
                    if connection.state == .disconnected, !host.isEmpty {
                        connection.connect(host: host, port: port == 0 ? 8765 : port)
                    }
                }
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild build -scheme MaverickRemote -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add client/
git commit -m "feat: add iOS UI — ConnectionView, SessionListView, ContentView, app entry"
```

---

## Task 13: End-to-End Manual Test

- [ ] **Step 1: Run MaverickAgent on your Mac**

Open `Maverick.xcodeproj` in Xcode, select the `MaverickAgent` scheme, run. A terminal icon should appear in the menu bar.

- [ ] **Step 2: Run MaverickRemote on iPhone simulator**

Select the `MaverickRemote` scheme with an iPhone simulator. Run.

- [ ] **Step 3: Connect**

In `ConnectionView`, enter `127.0.0.1` and port `8765`. Tap Connect.

- [ ] **Step 4: Create a session and verify terminal output**

Tap `+`, name it `test`. The terminal view should appear and show a shell prompt.

- [ ] **Step 5: Run Claude Code**

In the terminal, type `claude` and press enter. Verify Claude Code starts and the output renders correctly including ANSI colors.

- [ ] **Step 6: Test Ctrl+C**

While something is running, tap `^C` in the toolbar. Verify the process is interrupted.

- [ ] **Step 7: Test session persistence**

Background the iOS app for 10 seconds. Re-open it. Verify it reconnects and shows the scrollback.

- [ ] **Step 8: Test on real device over Tailscale**

Deploy MaverickRemote to a physical iPhone. Connect using the Mac's Tailscale hostname (e.g. `my-macbook.tail12345.ts.net`). Verify everything works over the Tailscale network.

- [ ] **Step 9: Final commit**

```bash
git add .
git commit -m "chore: complete end-to-end manual test verification"
```
