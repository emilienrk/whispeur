// OnboardingWindowController.swift
// Whispeur
//
// Hosts the first-launch setup in its own window. LSUIElement apps have no
// window by default, so the app has to be activated explicitly or the window
// opens behind whatever the user was doing.

import SwiftUI
import AppKit

@MainActor
final class OnboardingWindowController: NSObject {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(services: ServicesContainer) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(services: services) { [weak self] in
            services.settings.hasCompletedOnboarding = true
            self?.close()
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = String(localized: "Configuration de Whispeur")
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = NSHostingController(rootView: view)

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
