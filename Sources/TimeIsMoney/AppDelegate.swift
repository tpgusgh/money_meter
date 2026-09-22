import AppKit
import SwiftUI

/// Non-activating panel that can still become key, so its TextFields accept input
/// without the app stealing focus/activation from whatever the user is doing.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let panelSize = NSSize(width: 220, height: 400)

    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private let model = PayModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        setupStatusItem()
        setupPanel()
        checkForUpdate()
    }

    private func checkForUpdate() {
        // Dev (`swift run`) builds have no Info.plist version — nothing to compare against.
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        UpdateChecker.checkForUpdate(currentVersion: currentVersion) { [weak self] update in
            self?.model.availableUpdate = update
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wonsign.circle", accessibilityDescription: "Time Is Money")
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            // left click: reveal/toggle the detail panel like before
            model.toggleDetail()
            panel.orderFrontRegardless()
            return
        }

        // right click: recovery menu — the panel can get dragged off-screen
        // (isMovableByWindowBackground), so offer a way back in plus quit.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "패널 위치 초기화", action: #selector(resetPanelPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach so left-click keeps going through statusItemClicked
    }

    @objc private func resetPanelPosition() {
        positionPanelTopRight()
        panel.orderFrontRegardless()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func setupPanel() {
        let hosting = NSHostingController(rootView: MeterView(model: model))
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.level = .floating
        panel.hidesOnDeactivate = false // NSPanel defaults to true — was vanishing behind every other app
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false // MeterView draws its own shadow, scoped to its actual content size
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel

        positionPanelTopRight()
        panel.orderFrontRegardless() // force on-screen even though the app never activates
    }

    /// NSScreen.main follows whatever window currently has key focus (could be any app,
    /// on any monitor) — screens.first is the display that actually owns the menu bar.
    private func positionPanelTopRight() {
        guard let sf = NSScreen.screens.first?.visibleFrame else { return }
        let origin = NSPoint(x: sf.maxX - Self.panelSize.width - 16, y: sf.maxY - Self.panelSize.height - 16)
        // contentViewController assignment can reset the frame, so size+position are set
        // together instead of relying on panel.frame (which may read stale/zero right after).
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
    }
}
