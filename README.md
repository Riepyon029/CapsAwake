<p align="center"><img src="docs/icon.png" width="128" alt="Caps Awake — black and pink Caps Lock icon"></p>

# Caps Awake

**Caps Lockをひと押し。Macを、起こしたまま。**

黒とピンクをテーマにした、macOS用のスリープ防止タイマーです。Caps Lockキーと画面のボタンで開始・停止でき、メニューバーで残り時間を確認できます。

**[Macアプリをダウンロード](https://github.com/Riepyon029/CapsAwake/releases/latest/download/CapsAwake-Mac.zip)** · [リリース一覧](https://github.com/Riepyon029/CapsAwake/releases) · [不具合の報告](https://github.com/Riepyon029/CapsAwake/issues)

macOS 14以降 / Appleシリコン・Intel共通のUniversalアプリ。GitHubアカウントなしでダウンロードできます。

> この配布版はアドホック署名で、AppleのDeveloper ID署名・公証は未取得です。初回起動でmacOSの確認が必要になる場合があります。ふたを閉じた状態の動作は実機未検証です。機種・macOSによる制約は下記を確認してください。

## できること

- Caps Lockキー、アプリ内ボタン、メニューバーメニューから開始・停止。
- **30分・60分・90分・2時間・4時間・8時間・12時間・24時間**のタイマー。
- タイマー終了・停止・アプリ終了時に、開始前のスリープ設定を復元。
- アプリから20秒以上応答が途切れた場合は補助機能が自動解除。復元処理の時間が加わる場合があります。
- バッテリー駆動で残量10%以下、またはmacOSが温度をcriticalと報告した場合は自動解除。
- 画面の自動消灯はそのまま利用可能。アプリのウインドウを閉じてもメニューバーに常駐。
- 通信・広告・アクセス解析なし。文字入力の記録は行いません。

## インストール

1. [CapsAwake-Mac.zip](https://github.com/Riepyon029/CapsAwake/releases/latest/download/CapsAwake-Mac.zip)をダウンロードして展開します。リリースの「Source code」は開発者向けソースです。
2. `Caps Awake.app`を「アプリケーション」フォルダへ移動して開きます。
3. 「初回セットアップ」で、Macの管理者認証を使って補助機能をインストールします。ここではまだスリープ防止は開始しません。
4. Caps Lockで操作する場合は、アプリの「許可する」から **システム設定 → プライバシーとセキュリティ → 入力監視 → Caps Awake** をオンにします。macOSから求められた場合はアプリを再起動します。
5. 時間を選び、Caps Lockまたは「スタート」を押します。もう一度押すと停止します。

Caps Lock本来の大文字切り替えも動作します。別の機能に割り当てている場合は、画面のボタンを使用してください。入力監視の許可が不要なのは、ボタンだけで使う場合です。

### 初回起動でmacOSにブロックされる場合

このリポジトリのリリースから取得したことを確認してください。信頼できる配布元だと判断した場合は、一度アプリを開こうとした後、**システム設定 → プライバシーとセキュリティ → このまま開く**から、このアプリの起動を許可できます。管理対象のMacでは利用できない場合があります。[Appleの説明](https://support.apple.com/ja-jp/102445)

ダウンロードの整合性を確認するには、リリースの`SHA256SUMS.txt`とZIPを同じフォルダに置いて実行します。

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## ふたを閉じる動作と制約

通常のスリープ防止APIでは、MacBookのふたを閉じた際のスリープを防げません。そのため、管理者認証でインストールする補助機能が`pmset -a disablesleep`を使用します。この設定はMac全体に作用し、実行中は手動スリープにも影響します。

**ふたを閉じた状態の動作は未検証です。** すべての機種・macOSでの動作を保証するものではありません。最初は短い処理で、閉じた後も処理が続くことを確認してください。通気のよい場所で使い、バッグに入れる前には停止してください。

開始前からスリープが無効だった場合は、停止してもその元の設定を維持します。ほかの電源管理アプリと同時に設定を変更すると競合する可能性があります。補助機能を操作できるのは、セットアップしたmacOSユーザーです。

## アンインストール

アプリ右下の **「… → 補助機能をアンインストール」** を選んで管理者認証します。電源設定を復元し、補助機能を削除した後、アプリを終了してゴミ箱へ移動してください。アプリだけ削除すると補助機能は残ります。

補助機能の保存先:

| 用途 | パス |
| --- | --- |
| 実行ファイル | `/Library/PrivilegedHelperTools/local.capsawake.helper` |
| 起動設定 | `/Library/LaunchDaemons/local.capsawake.helper.plist` |
| 復元情報 | `/Library/Application Support/CapsAwake/recovery.json` |

## 開発・ビルド

macOSとXcodeのSwiftコンパイラが必要です。サードパーティのライブラリは使用していません。

```sh
git clone https://github.com/Riepyon029/CapsAwake.git
cd CapsAwake
bash test.sh
bash build.sh
open "dist/Caps Awake.app"
```

配布用ZIPとSHA-256チェックサムを作るには、`bash package.sh`を実行します。生成物は`dist/`に保存され、Gitには含まれません。ビルドはローカルのアドホック署名を使用し、開発用の秘密鍵や証明書を必要としません。

主な構成:

- `Sources/App/`: SwiftUI画面、AppKitメニューバー、Caps Lockの入力監視。
- `Sources/Helper/`: 管理者権限で動くlaunchd補助機能。
- `Sources/Shared/`: 通信形式、タイマーと電源設定の復元処理。
- `Tests/`: 実際の電源設定を変更しない自動テスト。
- `Resources/`: アイコン、使い方、アプリ情報。

補助機能はローカルのUnixソケットを使い、接続ユーザーIDを確認します。受け付ける操作は状態確認・開始・接続維持・停止だけです。電源設定を変更する前に元の値を保存し、再起動時にも復元を試みます。タイマーは壁時計の変更に左右されない連続時刻で計算します。

## 確認済みの範囲

- 自動テスト **62項目**: 全8タイマー、元の設定の保持、通信断、異常終了後の復元、復元失敗時の再試行、不正入力、通信タイムアウト。
- AppleシリコンのMacでアプリの起動、補助機能のインストール、ボタンによる開始・停止を確認。
- 2026年11月16日、実際のCaps Lockキー4回に対し、オン→オフ→オン→オフの4回の変化と、`SleepDisabled`の1→0→1→0を確認。
- Intel向けもビルド済みですが、Intel実機での実行と、ふたを閉じた状態の動作は未検証です。

初回公開版のv1.0.2は、確認済みのv1.0.1から配布案内とバージョン情報を更新したものです。キー処理・電源制御のロジックは同じです。

## English

Caps Awake is a black-and-pink macOS utility that toggles timed sleep prevention with Caps Lock, an on-screen button, or the menu bar. It offers 30, 60, and 90 minutes, plus 2, 4, 8, 12, and 24 hours. Download the universal Mac app from [Releases](https://github.com/Riepyon029/CapsAwake/releases/latest).

Requires macOS 14+, administrator authentication for the power helper, and Input Monitoring permission for the global Caps Lock shortcut. The build is ad-hoc signed and **not notarized**. Closed-lid operation is **not yet verified** and may vary by hardware and macOS. Use the in-app uninstall command to restore settings and remove the helper before deleting the app.

## 参考資料

- [Apple: スリープ・復帰通知と、ふたを閉じた場合の強制スリープ](https://developer.apple.com/library/archive/qa/qa1340/_index.html)
- [Apple公開ソース: pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Apple: Macでアプリを安全に開く](https://support.apple.com/ja-jp/102445)
