import Foundation

protocol PowerBackend: AnyObject {
    func readDisabled() throws -> Bool
    func setDisabled(_ value: Bool) throws
    func saveOriginal(_ value: Bool) throws
    func loadOriginal() throws -> Bool?
    func clearOriginal() throws
}

final class SessionController {
    private let backend: PowerBackend
    private(set) var original: Bool?
    private(set) var token: String?
    private(set) var deadline: Double = 0
    private(set) var heartbeat: Double = 0
    private(set) var duration: Int = 0
    private(set) var message = "準備ができました。"
    private var restorationFailed = false
    private var pendingRecoveryRead = false
    var active: Bool { original != nil }

    init(backend: PowerBackend) { self.backend = backend }

    func recover() {
        do {
            original = try backend.loadOriginal()
            pendingRecoveryRead = false
            if original != nil { try stop(reason: "前回の電源設定を復元しました。") }
        } catch {
            pendingRecoveryRead = original == nil
            restorationFailed = true
            message = "電源設定の復元を再試行中: \(error.localizedDescription)"
        }
    }

    func handle(_ request: HelperRequest, now: Double) -> HelperResponse {
        tick(now: now)
        do {
            guard request.version == Product.protocolVersion else { throw CapsError.message("アプリと補助機能のバージョンが一致しません。") }
            switch request.action {
            case "status": break
            case "start":
                guard !pendingRecoveryRead, !restorationFailed else { throw CapsError.message("前回の電源設定を復元中です。") }
                guard !active else { throw CapsError.message("すでに実行中です。停止してから開始してください。") }
                guard let seconds = request.seconds, Product.durations.contains(seconds / 60), seconds % 60 == 0,
                      let newToken = request.token, UUID(uuidString: newToken) != nil else {
                    throw CapsError.message("タイマー設定が正しくありません。")
                }
                let previous = try backend.readDisabled()
                try backend.saveOriginal(previous) // Write recovery data BEFORE changing global state.
                original = previous
                do { try backend.setDisabled(true) }
                catch {
                    let failure = error
                    try? stop(reason: "開始できませんでした。")
                    throw failure
                }
                duration = seconds
                deadline = now + Double(seconds)
                heartbeat = now
                token = newToken
                message = "ふたを閉じてもスリープを防止します。"
            case "heartbeat":
                guard active, request.token == token else { throw CapsError.message("セッションは終了しています。") }
                heartbeat = now
            case "stop": try stop(reason: "元の電源設定に戻しました。")
            default: throw CapsError.message("不明な操作です。")
            }
            return response(now: now, ok: !restorationFailed)
        } catch {
            return response(now: now, ok: false, error: error.localizedDescription)
        }
    }

    func tick(now: Double) {
        if pendingRecoveryRead { recover(); return }
        guard active else { return }
        if restorationFailed || token == nil {
            try? stop(reason: "元の電源設定に戻しました。")
        } else if now >= deadline {
            try? stop(reason: "タイマーが終了しました。")
        } else if now - heartbeat >= 20 {
            try? stop(reason: "アプリとの接続が切れたため、自動解除しました。")
        }
    }

    func stop(reason: String) throws {
        guard let previous = original else { return }
        do {
            try backend.setDisabled(previous)
            try backend.clearOriginal()
            original = nil
            token = nil
            deadline = 0
            duration = 0
            restorationFailed = false
            message = reason
        } catch {
            restorationFailed = true
            message = "電源設定の復元を再試行中: \(error.localizedDescription)"
            throw error
        }
    }

    func response(now: Double, ok: Bool = true, error: String? = nil) -> HelperResponse {
        HelperResponse(ok: ok, active: active, remaining: active ? max(0, Int(ceil(deadline - now))) : 0,
                       duration: duration, message: error ?? message, ownerToken: token, originalDisabled: original ?? false)
    }
}
