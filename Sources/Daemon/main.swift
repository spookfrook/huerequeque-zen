import Darwin
import Foundation

private func logLine(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)\n"
    fputs(line, stderr)
    try? FileManager.default.createDirectory(atPath: ZenConstants.logDir, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: ZenConstants.logFilePath)
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

private func loadAllowedUIDs() -> Set<uid_t> {
    var uids: Set<uid_t> = [0]
    if let raw = try? String(contentsOfFile: ZenConstants.ownerUIDPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
       let uid = UInt32(raw) {
        uids.insert(uid_t(uid))
    }
    return uids
}

// Ignore SIGPIPE so client disconnects never kill the daemon
signal(SIGPIPE, SIG_IGN)

logLine("Huerequeque Zen daemon v\(ZenConstants.daemonVersion) starting (euid=\(geteuid()))")

let blocker = MacOSSystemBlocker()
let core = DaemonCore(blocker: blocker)
core.bootstrapEnforcement()

let allowedUIDs = loadAllowedUIDs()
let server = SocketServer(socketPath: ZenConstants.socketPath, allowedUIDs: allowedUIDs)

do {
    try server.start { request in
        core.handle(request)
    }
    logLine("Listening on \(ZenConstants.socketPath) for UIDs \(allowedUIDs.sorted())")
} catch {
    logLine("FATAL: failed to start socket server: \(error.localizedDescription)")
    exit(1)
}

var tickCount: UInt64 = 0
let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(100))
timer.setEventHandler {
    tickCount &+= 1
    let checkIntegrity = (tickCount % 15 == 0)
    let refreshIPs = (tickCount % 120 == 0)
    core.tick(checkIntegrity: checkIntegrity, forceIPRefresh: refreshIPs)
}
timer.resume()

// Handle SIGTERM cleanly without lifting any active block (launchd will restart if KeepAlive)
signal(SIGTERM, SIG_IGN)
let sigTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigTerm.setEventHandler {
    logLine("Received SIGTERM; preserving active blocks and exiting.")
    timer.cancel()
    server.stop()
    exit(0)
}
sigTerm.resume()

dispatchMain()
