import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            
            // Remove native styles that enforce a border
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask = .borderless
            window.hasShadow = false

            // Apply corner radius to the content view layer
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 15
                contentView.layer?.masksToBounds = true
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
