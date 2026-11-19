import SwiftUI

private let ink = Color(red: 0.043, green: 0.039, blue: 0.051)
private let panel = Color(red: 0.105, green: 0.090, blue: 0.110)
private let accent = Color(red: 1, green: 0.45, blue: 0.69)
private let muted = Color(red: 0.63, green: 0.58, blue: 0.63)

struct ContentView: View {
    @ObservedObject var model: AwakeModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "capslock.fill").font(.system(size: 21, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CAPS AWAKE").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(2.1)
                    Text("Macを、起こしておこう。").font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.active ? accent : muted).frame(width: 6, height: 6)
                    Text(model.active ? "AWAKE" : "STANDBY").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.7)
                }
                .foregroundStyle(model.active ? accent : muted)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Capsule().fill(panel))
            }
            .padding(.bottom, 24)

            ZStack {
                Circle().stroke(Color.white.opacity(0.05), lineWidth: 2)
                Circle().trim(from: 0, to: model.progress)
                    .stroke(accent.opacity(model.active ? 0.95 : 0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 11) {
                    Image(systemName: model.active ? "sun.max" : "moon")
                        .font(.system(size: 23, weight: .light)).foregroundStyle(accent)
                    Text(model.clockText)
                        .font(.system(size: model.clockText.count > 5 ? 39 : 48, weight: .light, design: .rounded))
                        .monospacedDigit().tracking(-1.4)
                        .contentTransition(.numericText())
                        .accessibilityLabel("残り時間 \(model.clockText)")
                    Text(model.active ? "自動解除まで" : "スリープ防止タイマー")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
            }.frame(width: 220, height: 220)
                .padding(.bottom, 20)

            Text(model.active ? "閉じても、作業はそのまま。" : "ひと押しで、Macを起こしたまま。")
                .font(.system(size: 16, weight: .medium))
                .padding(.bottom, 7)
            Text(model.active ? "タイマー終了時に元の電源設定へ戻ります。" : "ふたを閉じている間も、スリープを防ぎます。")
                .font(.system(size: 11)).foregroundStyle(muted)
                .padding(.bottom, 23)

            HStack {
                Text("TIMER").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.8)
                Spacer()
                Text(model.active ? "変更するには一度停止" : "時間を選択")
                    .font(.system(size: 10))
            }.foregroundStyle(muted).padding(.bottom, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Product.durations, id: \.self) { minutes in
                    Button { model.select(minutes) } label: {
                        Text(Product.label(minutes: minutes))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 39)
                            .foregroundStyle(model.selectedMinutes == minutes ? accent : Color.white.opacity(0.72))
                            .background(RoundedRectangle(cornerRadius: 10).fill(model.selectedMinutes == minutes ? accent.opacity(0.11) : panel))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedMinutes == minutes ? accent.opacity(0.55) : Color.white.opacity(0.035), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(model.active || model.busy)
                        .accessibilityLabel("\(Product.label(minutes: minutes))タイマー")
                        .accessibilityAddTraits(model.selectedMinutes == minutes ? .isSelected : [])
                }
            }.padding(.bottom, 17)

            Button { model.toggle() } label: {
                HStack(spacing: 9) {
                    if model.busy { ProgressView().controlSize(.small).tint(ink) }
                    else { Image(systemName: model.active ? "stop.fill" : model.ready ? "capslock" : "lock.open").font(.system(size: 15, weight: .semibold)) }
                    Text(model.busy ? "設定中…" : model.active ? "スリープ防止を停止" : model.ready ? "スタート" : "初回セットアップ")
                        .font(.system(size: 14, weight: .semibold))
                    if model.ready && !model.active && !model.busy {
                        Text("⇪ CAPS").font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                }.foregroundStyle(ink).frame(maxWidth: .infinity).frame(height: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(model.busy)
                .padding(.bottom, 16)

            HStack(spacing: 11) {
                Text("⇪").font(.system(size: 20, weight: .medium))
                    .frame(width: 35, height: 35).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Caps Lockでオン / オフ").font(.system(size: 11, weight: .medium))
                    Text(model.capsReady ? "通常のCaps Lock入力も切り替わります" : "「入力監視」の許可が必要です")
                        .font(.system(size: 9)).foregroundStyle(muted)
                }
                Spacer(minLength: 3)
                if model.capsReady {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(accent)
                        .accessibilityLabel("Caps Lock有効")
                } else {
                    Button("許可する") { model.enableCaps() }
                        .font(.system(size: 10, weight: .semibold)).buttonStyle(.plain).foregroundStyle(accent)
                }
            }.padding(12).background(panel, in: RoundedRectangle(cornerRadius: 12))

            if let error = model.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.system(size: 10)).foregroundStyle(accent).padding(.top, 10)
            } else if model.active && model.originalDisabled {
                Text("開始前からスリープ無効でした。終了後も元の設定を維持します。")
                    .font(.system(size: 9)).foregroundStyle(muted).padding(.top, 10)
            } else if model.ready && !model.active && model.message != "準備ができました。" {
                Text(model.message).font(.system(size: 10)).foregroundStyle(muted).padding(.top, 10)
            }

            Spacer(minLength: 13)
            HStack(spacing: 5) {
                Image(systemName: "battery.25percent")
                Text("残量10%以下で自動解除")
                Spacer()
                Menu {
                    Button("使い方") { AppDelegate.current?.showHelp() }
                    Button("補助機能を再設定") { model.setup() }
                    Button("補助機能をアンインストール") { model.uninstallHelper() }
                    Divider()
                    Button("Caps Awakeを終了") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("その他の操作")
            }.font(.system(size: 9)).foregroundStyle(muted)
            Text("通気のよい場所で使用してください。")
                .font(.system(size: 9)).foregroundStyle(muted.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
        .padding(.horizontal, 30).padding(.top, 20).padding(.bottom, 19)
        .frame(width: 460, height: 770)
        .background(ink).foregroundStyle(Color(red: 0.92, green: 0.93, blue: 0.92))
        .preferredColorScheme(.dark)
    }
}
