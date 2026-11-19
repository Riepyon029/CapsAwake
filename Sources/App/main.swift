import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var current: AppDelegate?
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var model: AwakeModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        // Refresh the running app's Dock icon instead of retaining an earlier cached design.
        if let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let preview = CommandLine.arguments.contains("--ui-preview")
        if !preview, let bundleID = Bundle.main.bundleIdentifier {
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            if let existing { existing.activate(); NSApp.terminate(nil); return }
        }
        model = AwakeModel(preview: preview)
        model.onChange = { [weak self] in self?.updateStatus() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 798),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = preview ? "Caps Awake — Preview" : "Caps Awake"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.043, green: 0.039, blue: 0.051, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        createMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatus()
        showWindow()
    }

    func createMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Caps Awakeについて", action: #selector(showHelp), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "ウインドウを表示", action: #selector(showWindow), keyEquivalent: "1")
        appMenu.addItem(withTitle: "隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Caps Awakeを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; main.addItem(item); NSApp.mainMenu = main
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: model.active ? "capslock.fill" : "capslock", accessibilityDescription: "Caps Awake")
        button.image?.isTemplate = true
        button.title = model.active ? " " + model.clockText : ""
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.toolTip = model.active ? "Caps Awake: 残り \(model.clockText)" : "Caps Awakeを開く"
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Caps Awakeを開く", action: #selector(showWindow), keyEquivalent: "")
            let toggle = menu.addItem(withTitle: model.active ? "スリープ防止を停止" : "スリープ防止を開始", action: #selector(toggle), keyEquivalent: "")
            toggle.isEnabled = !model.busy
            menu.addItem(.separator())
            menu.addItem(withTitle: "終了（スリープ防止を解除）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { showWindow() }
    }
    @objc func toggle() { model.toggle() }
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showHelp() {
        if let url = Bundle.main.url(forResource: "Help", withExtension: "html") { NSWorkspace.shared.open(url) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
