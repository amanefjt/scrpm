import AppKit
import SwiftUI

private final class OverlayWindow: NSWindow {
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0 }
}

final class OverlayWindowController {
    private var windows: [NSWindow] = []
    private var eventMonitor: Any?

    func show(timerManager: TimerStateManager) {
        guard windows.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.collectionBehavior = [.fullScreenPrimary]
            window.backgroundColor = .black
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = true
            window.ignoresMouseEvents = false
            window.animationBehavior = .none

            let hostingView = NSHostingView(rootView:
                BreakOverlayView()
                    .environment(timerManager)
            )
            window.contentView = hostingView
            window.setFrame(screen.frame, display: false)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
            windows.append(window)
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { return nil } // ESC を無効化
            return event
        }
    }

    func hide() {
        // Detach SwiftUI content immediately to stop @Observable updates on dying view
        windows.forEach { $0.contentView = nil }

        let windowsToClose = windows
        windows.removeAll()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        DispatchQueue.main.async {
            windowsToClose.forEach {
                $0.isReleasedWhenClosed = false
                $0.close()
            }
        }
    }
}
