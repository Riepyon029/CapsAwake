import AppKit
import SwiftUI
import ApplicationServices

final class CapsListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var previous = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    var onPress: (() -> Void)?
    var listening: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess() else { return false }
        previous = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                               eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<CapsListener>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == 57 {
                let current = event.flags.contains(.maskAlphaShift)
                if current != listener.previous {
                    listener.previous = current
                    DispatchQueue.main.async { listener.onPress?() }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }
    deinit { stop() }
}

final class AwakeModel: ObservableObject {
    @Published var selectedMinutes: Int = {
        let saved = UserDefaults.standard.integer(forKey: "timerMinutes")
        return Product.durations.contains(saved) ? saved : 60
    }()
    @Published var active = false
    @Published var remaining = 0
    @Published var duration = 0
    @Published var ready = false
    @Published var busy = false
    @Published var capsReady = false
    @Published var message = "タイマーを選んで、準備を始めましょう。"
    @Published var error: String?
    @Published var originalDisabled = false
    var onChange: (() -> Void)?
    let preview: Bool
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "local.capsawake.client", qos: .userInitiated)
    private var timer: Timer?
    private var listener = CapsListener()
    private var polling = false
    private var lastRemainingAt = continuousSeconds()
    private var remainingAtReply = 0
    private var lastPoll = 0.0
    private var activity: NSObjectProtocol?

    init(preview: Bool = false) {
        self.preview = preview
        listener.onPress = { [weak self] in self?.toggle() }
        if preview {
            ready = true; capsReady = true
            message = "時間を選んで、Caps Lockでスタート。"
        } else {
            capsReady = listener.start()
            poll()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var clockText: String {
        let seconds = active ? remaining : selectedMinutes * 60
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    var progress: Double { active && duration > 0 ? max(0, min(1, Double(remaining) / Double(duration))) : 1 }

    func select(_ minutes: Int) {
        guard !active, !busy, Product.durations.contains(minutes) else { return }
        selectedMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "timerMinutes")
        onChange?()
    }

    private func tick() {
        if active { remaining = max(0, remainingAtReply - Int(continuousSeconds() - lastRemainingAt)) }
        if !preview && continuousSeconds() - lastPoll >= 3 {
            poll()
            if !capsReady { capsReady = listener.start() }
        }
        onChange?()
    }

    private func apply(_ reply: HelperResponse) {
        ready = true
        active = reply.active
        remaining = reply.remaining
        remainingAtReply = reply.remaining
        lastRemainingAt = continuousSeconds()
        duration = reply.duration
        originalDisabled = reply.originalDisabled
        message = reply.message
        if active && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Caps Awakeのタイマーと接続監視")
        } else if !active, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if !reply.ok { error = reply.message }
        onChange?()
    }

    func poll() {
        guard !preview, !polling, !busy else { return }
        polling = true
        lastPoll = continuousSeconds()
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { () -> HelperResponse in
                let status = try helperCall(HelperRequest(action: "status"))
                if status.active && status.ownerToken == self.token {
                    return try helperCall(HelperRequest(action: "heartbeat", token: self.token))
                }
                return status
            }
            DispatchQueue.main.async {
                self.polling = false
                switch result {
                case .success(let response): self.apply(response)
                case .failure:
                    self.ready = false
                    if self.active {
                        self.error = "補助機能との接続を確認中です。アプリとの接続が20秒以上途切れると自動解除されます。"
                    }
                    self.onChange?()
                }
            }
        }
    }

    func toggle() {
        guard !busy else { return }
        if !ready { setup(); return }
        error = nil
        if preview {
            active.toggle(); duration = selectedMinutes * 60; remaining = duration
            remainingAtReply = remaining; lastRemainingAt = continuousSeconds()
            message = active ? "ふたを閉じてもスリープを防止します。" : "元の電源設定に戻しました。"
            onChange?(); return
        }
        busy = true
        let request = active ? HelperRequest(action: "stop") : HelperRequest(action: "start", seconds: selectedMinutes * 60, token: token)
        queue.async { [weak self] in
            let result = Result { try helperCall(request) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let reply): self.apply(reply)
                case .failure(let error): self.error = error.localizedDescription; self.poll()
                }
            }
        }
    }

    func setup() {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "ふたを閉じても使えるようにする"
        alert.informativeText = "スリープ設定を扱う補助機能をインストールします。次の画面でMacの管理者パスワードまたはTouch IDによる認証が必要です。タイマー終了・停止・アプリ終了時に元の設定へ戻します。\n\n設定後、「スタート」で開始します。"
        alert.addButton(withTitle: "セットアップ")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installHelper(action: "install \(getuid())")
    }

    private func installHelper(action: String) {
        guard let helper = Bundle.main.url(forResource: "CapsAwakeHelper", withExtension: nil) else {
            error = "補助機能が見つかりません。アプリを再ビルドしてください。"; return
        }
        busy = true; error = nil
        let quotedPath = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = quotedPath + " " + action
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        queue.async { [weak self] in
            // osascript runs outside the UI process so the authorization dialog never freezes the app.
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardError = pipe; process.standardOutput = pipe
            var failure: String?
            do {
                try process.run()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    failure = output.contains("-128") ? "セットアップをキャンセルしました。" : "セットアップできませんでした。\n\(output)"
                }
            } catch { failure = error.localizedDescription }
            let finalFailure = failure
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.error = finalFailure
                if action == "uninstall", finalFailure == nil {
                    self.ready = false; self.active = false
                    self.message = "補助機能を削除しました。"
                } else { self.poll() }
            }
        }
    }

    func uninstallHelper() {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "補助機能をアンインストール"
        alert.informativeText = "実行中のスリープ防止を解除して、電源設定を復元し、補助機能を削除します。Macの管理者認証が必要です。"
        alert.addButton(withTitle: "削除する"); alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn { installHelper(action: "uninstall") }
    }

    func enableCaps() {
        guard !preview else { return }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        capsReady = listener.start()
        if !capsReady, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func shutdown() {
        timer?.invalidate(); listener.stop()
        if !preview { _ = try? helperCall(HelperRequest(action: "stop")) }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
}
