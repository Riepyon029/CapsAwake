import Foundation
import Darwin

enum Product {
    static let version = "1.0.2"
    static let protocolVersion = 1
    static let label = "local.capsawake.helper"
    static let socketPath = "/var/run/local.capsawake.sock"
    static let helperPath = "/Library/PrivilegedHelperTools/local.capsawake.helper"
    static let plistPath = "/Library/LaunchDaemons/local.capsawake.helper.plist"
    static let stateDirectory = "/Library/Application Support/CapsAwake"
    static let durations = [30, 60, 90, 120, 240, 480, 720, 1440]
    static func label(minutes: Int) -> String {
        minutes < 120 ? "\(minutes)分" : "\(minutes / 60)時間"
    }
}

struct HelperRequest: Codable {
    var action: String
    var seconds: Int?
    var token: String?
    var version = Product.protocolVersion
}

struct HelperResponse: Codable {
    var ok: Bool
    var active: Bool
    var remaining: Int
    var duration: Int
    var message: String
    var ownerToken: String?
    var originalDisabled: Bool
    var version = Product.protocolVersion
}

enum CapsError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

func continuousSeconds() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
}

func unixAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw CapsError.message("通信先のパスが長すぎます。")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        for (i, byte) in bytes.enumerated() { destination[i] = UInt8(bitPattern: byte) }
    }
    return address
}

func setSocketTimeout(_ fd: Int32) {
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    var one: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
}

func writePacket<T: Encodable>(_ value: T, to fd: Int32) throws {
    var data = try JSONEncoder().encode(value)
    data.append(10)
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            guard written > 0 else { throw CapsError.message("補助機能との通信が切れました。") }
            offset += written
        }
    }
}

func readPacket<T: Decodable>(_ type: T.Type, from fd: Int32) throws -> T {
    var data = Data()
    var byte: UInt8 = 0
    let deadline = continuousSeconds() + 2
    while data.count < 4096 {
        guard continuousSeconds() < deadline else { throw CapsError.message("補助機能との通信がタイムアウトしました。") }
        let count = Darwin.read(fd, &byte, 1)
        guard count == 1 else { throw CapsError.message("補助機能から応答がありません。") }
        if byte == 10 { return try JSONDecoder().decode(type, from: data) }
        data.append(byte)
    }
    throw CapsError.message("通信データが大きすぎます。")
}

func helperCall(_ request: HelperRequest) throws -> HelperResponse {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CapsError.message("通信を開始できません。") }
    defer { close(fd) }
    setSocketTimeout(fd)
    var address = try unixAddress(Product.socketPath)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { throw CapsError.message("初回セットアップが必要です。") }
    var peerUID: uid_t = 99999
    var peerGID: gid_t = 99999
    guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == 0 else {
        throw CapsError.message("補助機能の認証に失敗しました。")
    }
    try writePacket(request, to: fd)
    let response = try readPacket(HelperResponse.self, from: fd)
    guard response.version == Product.protocolVersion else {
        throw CapsError.message("補助機能を更新してください。")
    }
    return response
}
