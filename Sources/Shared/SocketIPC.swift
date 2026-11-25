import Darwin
import Foundation

enum SocketIPCError: Error, LocalizedError {
    case socketCreationFailed(Int32)
    case pathTooLong
    case connectFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case writeFailed
    case readFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let code): return "No se pudo crear el socket (\(code))."
        case .pathTooLong: return "Ruta del socket demasiado larga."
        case .connectFailed: return "El guardián irrompible no está activo."
        case .bindFailed(let code): return "No se pudo enlazar el socket (\(code))."
        case .listenFailed(let code): return "No se pudo escuchar en el socket (\(code))."
        case .writeFailed: return "Error al enviar comando al guardián."
        case .readFailed: return "Sin respuesta del guardián."
        case .invalidResponse: return "Respuesta inválida del guardián."
        }
    }
}

enum SocketJSON {
    static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}

private func makeUnixAddr(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count <= maxLen else { throw SocketIPCError.pathTooLong }
    withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
        for i in 0..<bytes.count {
            rawBuf[i] = UInt8(bitPattern: bytes[i])
        }
    }
    return addr
}

private func setSocketTimeout(_ fd: Int32, seconds: Int) {
    var tv = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}

private func writeAll(_ fd: Int32, data: Data) -> Bool {
    return data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return false }
        var sent = 0
        while sent < data.count {
            let n = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
            if n <= 0 {
                if errno == EINTR { continue }
                return false
            }
            sent += n
        }
        return true
    }
}

private func readLine(_ fd: Int32, maxBytes: Int = 256 * 1024) -> Data? {
    var result = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while result.count < maxBytes {
        let n = Darwin.read(fd, &buf, buf.count)
        if n < 0 {
            if errno == EINTR { continue }
            return nil
        }
        if n == 0 { break }
        if let newlineIndex = buf[0..<n].firstIndex(of: 0x0A) {
            result.append(contentsOf: buf[0..<newlineIndex])
            return result
        }
        result.append(contentsOf: buf[0..<n])
    }
    return result.isEmpty ? nil : result
}

final class SocketClient {
    let socketPath: String

    init(socketPath: String = ZenConstants.socketPath) {
        self.socketPath = socketPath
    }

    func send(_ request: DaemonRequest, timeoutSeconds: Int = 4) throws -> DaemonResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketIPCError.socketCreationFailed(errno) }
        defer { Darwin.close(fd) }

        setSocketTimeout(fd, seconds: timeoutSeconds)
        var addr = try makeUnixAddr(socketPath)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRes == 0 else { throw SocketIPCError.connectFailed(errno) }

        var payload = try SocketJSON.encoder().encode(request)
        payload.append(0x0A)
        guard writeAll(fd, data: payload) else { throw SocketIPCError.writeFailed }

        guard let replyData = readLine(fd) else { throw SocketIPCError.readFailed }
        guard let response = try? SocketJSON.decoder().decode(DaemonResponse.self, from: replyData) else {
            throw SocketIPCError.invalidResponse
        }
        return response
    }
}

final class SocketServer {
    let socketPath: String
    let allowedUIDs: Set<uid_t>
    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.santiagodetuna.huerequeque-zen.socket")

    init(socketPath: String = ZenConstants.socketPath, allowedUIDs: Set<uid_t>) {
        self.socketPath = socketPath
        self.allowedUIDs = allowedUIDs
    }

    func start(handler: @escaping (DaemonRequest) -> DaemonResponse) throws {
        unlink(socketPath)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketIPCError.socketCreationFailed(errno) }

        var addr = try makeUnixAddr(socketPath)
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindRes == 0 else {
            let err = errno
            Darwin.close(fd)
            throw SocketIPCError.bindFailed(err)
        }

        // Allow connecting from local user; getpeereid enforces exact UID authorization.
        chmod(socketPath, 0o666)

        guard Darwin.listen(fd, 16) == 0 else {
            let err = errno
            Darwin.close(fd)
            throw SocketIPCError.listenFailed(err)
        }

        self.serverFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptClient(handler: handler)
        }
        src.setCancelHandler { [fd] in
            Darwin.close(fd)
        }
        self.source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        serverFD = -1
        unlink(socketPath)
    }

    private func acceptClient(handler: @escaping (DaemonRequest) -> DaemonResponse) {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(serverFD, sockPtr, &addrLen)
            }
        }
        guard clientFD >= 0 else { return }
        defer { Darwin.close(clientFD) }

        setSocketTimeout(clientFD, seconds: 4)

        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0 else { return }
        if !allowedUIDs.isEmpty && !allowedUIDs.contains(peerUID) && peerUID != 0 {
            let denied = DaemonResponse(ok: false, message: "Usuario no autorizado.", state: nil)
            if var data = try? SocketJSON.encoder().encode(denied) {
                data.append(0x0A)
                _ = writeAll(clientFD, data: data)
            }
            return
        }

        guard let reqData = readLine(clientFD) else { return }
        let response: DaemonResponse
        if let req = try? SocketJSON.decoder().decode(DaemonRequest.self, from: reqData) {
            response = handler(req)
        } else {
            response = DaemonResponse(ok: false, message: "Solicitud JSON inválida.", state: nil)
        }

        if var reply = try? SocketJSON.encoder().encode(response) {
            reply.append(0x0A)
            _ = writeAll(clientFD, data: reply)
        }
    }
}
