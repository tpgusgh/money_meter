import AppKit
import SwiftUI

/// Non-activating panel that can still become key, so its TextFields accept input
/// without the app stealing focus/activation from whatever the user is doing.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private let model = PayModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        setupStatusItem()
        setupPanel()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wonsign.circle", accessibilityDescription: "Time Is Money")
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.target = self
    }

    @objc private func togglePanel() {
        model.toggleDetail()
        panel.orderFrontRegardless() // stays forced on-screen; this just reveals detail controls
    }

    private func setupPanel() {
        let panelSize = NSSize(width: 220, height: 400)
        let hosting = NSHostingController(rootView: MeterView(model: model))
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false // MeterView draws its own shadow, scoped to its actual content size
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel

        // contentViewController assignment can reset the frame, so size+position are set
        // together afterward instead of relying on panel.frame (which may read stale/zero here).
        // NSScreen.main follows whatever window currently has key focus (could be any app,
        // on any monitor) — screens.first is the display that actually owns the menu bar.
        if let sf = NSScreen.screens.first?.visibleFrame {
            let origin = NSPoint(x: sf.maxX - panelSize.width - 16, y: sf.maxY - panelSize.height - 16)
            panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        }
        panel.orderFrontRegardless() // force on-screen even though the app never activates
    }
}
