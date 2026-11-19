import Foundation
import Darwin
import IOKit.ps

private var shouldExit = false

@discardableResult
func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    if process.terminationStatus != 0 && !allowFailure {
        throw CapsError.message("\(URL(fileURLWithPath: executable).lastPathComponent): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return output
}

struct Recovery: Codable { let schema: Int; let disabled: Bool }

final class SystemPower: PowerBackend {
    let recoveryPath = Product.stateDirectory + "/recovery.json"
    func readDisabled() throws -> Bool {
        let text = try run("/usr/bin/pmset", ["-g"])
        for line in text.split(separator: "\n") {
            let words = line.split(whereSeparator: { $0.isWhitespace })
            if words.first == "SleepDisabled", words.count == 2 {
                if words[1] == "0" { return false }
                if words[1] == "1" { return true }
            }
        }
        throw CapsError.message("このMacのスリープ設定を読み取れません。設定は変更していません。")
    }
    func setDisabled(_ value: Bool) throws {
        try run("/usr/bin/pmset", ["-a", "disablesleep", value ? "1" : "0"])
        guard try readDisabled() == value else { throw CapsError.message("電源設定の変更を確認できませんでした。") }
    }
    func saveOriginal(_ value: Bool) throws {
        let data = try JSONEncoder().encode(Recovery(schema: 1, disabled: value))
        try data.write(to: URL(fileURLWithPath: recoveryPath), options: .atomic)
        guard chmod(recoveryPath, 0o600) == 0 else { throw CapsError.message("復元情報を保護できません。") }
        // Flush the recovery record before pmset can persist a change.
        let fd = open(recoveryPath, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CapsError.message("復元情報を保存できません。") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw CapsError.message("復元情報を同期できません。") }
    }
    func loadOriginal() throws -> Bool? {
        guard FileManager.default.fileExists(atPath: recoveryPath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: recoveryPath))
        let record = try JSONDecoder().decode(Recovery.self, from: data)
        guard record.schema == 1 else { throw CapsError.message("復元情報の形式を確認してください。") }
        return record.disabled
    }
    func clearOriginal() throws {
        if FileManager.default.fileExists(atPath: recoveryPath) { try FileManager.default.removeItem(atPath: recoveryPath) }
    }
}

func ensureRootDirectory(_ path: String, mode: mode_t) throws {
    var metadata = stat()
    if lstat(path, &metadata) == 0 {
        guard (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == 0,
              metadata.st_mode & 0o022 == 0 else { throw CapsError.message("安全でない保存先です: \(path)") }
    } else {
        guard errno == ENOENT, mkdir(path, mode) == 0 else { throw CapsError.message("保存先を作成できません: \(path)") }
    }
}

func removeSocket() {
    var metadata = stat()
    if lstat(Product.socketPath, &metadata) == 0, metadata.st_uid == 0,
       (metadata.st_mode & S_IFMT) == S_IFSOCK { unlink(Product.socketPath) }
}

func install(for uid: uid_t) throws {
    guard uid >= 501 else { throw CapsError.message("ユーザーを確認できません。") }
    try ensureRootDirectory("/Library/PrivilegedHelperTools", mode: 0o755)
    try ensureRootDirectory(Product.stateDirectory, mode: 0o700)
    try run("/bin/launchctl", ["bootout", "system/" + Product.label], allowFailure: true)
    let old = SystemPower()
    if let value = try old.loadOriginal() { try old.setDisabled(value); try old.clearOriginal() }
    let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let destination = URL(fileURLWithPath: Product.helperPath)
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".capsawake-" + UUID().uuidString)
    try FileManager.default.copyItem(at: source, to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard chown(temporary.path, 0, 0) == 0, chmod(temporary.path, 0o755) == 0,
          rename(temporary.path, destination.path) == 0 else { throw CapsError.message("補助機能を配置できません。") }
    let plist: [String: Any] = [
        "Label": Product.label,
        "ProgramArguments": [Product.helperPath, "serve", String(uid)],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ThrottleInterval": 2,
        "ProcessType": "Background",
        "ExitTimeOut": 10,
        "Umask": 0o077
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: Product.plistPath), options: .atomic)
    guard chown(Product.plistPath, 0, 0) == 0, chmod(Product.plistPath, 0o644) == 0 else {
        throw CapsError.message("起動設定を保護できません。")
    }
    try run("/bin/launchctl", ["enable", "system/" + Product.label])
    try run("/bin/launchctl", ["bootstrap", "system", Product.plistPath])
}

func uninstall() throws {
    try run("/bin/launchctl", ["bootout", "system/" + Product.label], allowFailure: true)
    let backend = SystemPower()
    if let previous = try backend.loadOriginal() { try backend.setDisabled(previous); try backend.clearOriginal() }
    for path in [Product.plistPath, Product.helperPath] {
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
    }
    removeSocket()
    // Remove only our empty directory. Never recursively remove an administrator's files.
    _ = rmdir(Product.stateDirectory)
}

func batteryIsLow() -> Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return false }
    for source in sources {
        guard let details = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              details[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
              let current = details[kIOPSCurrentCapacityKey] as? Int,
              let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
        if Double(current) / Double(maximum) <= 0.10 { return true }
    }
    return false
}

func serve(uid: uid_t) throws {
    guard uid >= 501 else { throw CapsError.message("許可ユーザーが不正です。") }
    try ensureRootDirectory(Product.stateDirectory, mode: 0o700)
    let controller = SessionController(backend: SystemPower())
    controller.recover() // Also runs after a crash or restart, before accepting a session.
    signal(SIGTERM) { _ in shouldExit = true }
    signal(SIGINT) { _ in shouldExit = true }
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw CapsError.message("ソケットを作成できません。") }
    defer { close(listener); removeSocket(); try? controller.stop(reason: "補助機能を終了しました。") }
    removeSocket()
    var address = try unixAddress(Product.socketPath)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0, chmod(Product.socketPath, 0o666) == 0, listen(listener, 8) == 0 else {
        throw CapsError.message("通信の待受を開始できません。")
    }
    var lastSafetyCheck: Double = 0
    while !shouldExit {
        let now = continuousSeconds()
        controller.tick(now: now)
        if controller.active && now - lastSafetyCheck >= 5 {
            lastSafetyCheck = now
            if batteryIsLow() { try? controller.stop(reason: "バッテリー残量が10%以下のため、自動解除しました。") }
            if ProcessInfo.processInfo.thermalState == .critical { try? controller.stop(reason: "Macの温度が高いため、自動解除しました。") }
        }
        var event = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&event, 1, 1000) > 0, event.revents & Int16(POLLIN) != 0 else { continue }
        let client = accept(listener, nil, nil)
        guard client >= 0 else { continue }
        do {
            defer { close(client) }
            setSocketTimeout(client)
            var peer: uid_t = 99999
            var group: gid_t = 99999
            guard getpeereid(client, &peer, &group) == 0, peer == uid || peer == 0 else { continue }
            let request = try readPacket(HelperRequest.self, from: client)
            if request.action == "start" && (batteryIsLow() || ProcessInfo.processInfo.thermalState == .critical) {
                try writePacket(controller.response(now: continuousSeconds(), ok: false, error: "バッテリー残量またはMacの温度を確認してください。"), to: client)
            } else {
                try writePacket(controller.handle(request, now: continuousSeconds()), to: client)
            }
        } catch { /* Invalid or disconnected clients never change the power state. */ }
    }
}

@main
enum HelperMain {
    static func main() {
        do {
            if CommandLine.arguments.contains("--check") {
                print("Caps Awake helper \(Product.version); SleepDisabled=\(try SystemPower().readDisabled()); uid=\(getuid())")
                return
            }
            guard geteuid() == 0 else { throw CapsError.message("この操作には管理者認証が必要です。") }
            let args = CommandLine.arguments
            switch args.dropFirst().first {
            case "install":
                guard args.count == 3, let uid = uid_t(args[2]) else { throw CapsError.message("引数が不正です。") }
                try install(for: uid)
            case "serve":
                guard args.count == 3, let uid = uid_t(args[2]) else { throw CapsError.message("引数が不正です。") }
                try serve(uid: uid)
            case "uninstall": try uninstall()
            default: throw CapsError.message("不明な操作です。")
            }
        } catch {
            fputs("Caps Awake: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
