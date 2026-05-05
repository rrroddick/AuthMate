import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// NSView subclass so styling runs in viewDidMoveToWindow, which fires deterministically
// when the view enters the window hierarchy — unlike DispatchQueue.main.async, which
// has no guarantee that view.window is non-nil by the next runloop tick for MenuBarExtra.
private final class ConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = .borderless
        window.hasShadow = false
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 15
            contentView.layer?.masksToBounds = true
        }
    }
}
