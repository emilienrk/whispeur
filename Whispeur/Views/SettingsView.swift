// SettingsView.swift
// Whispeur
//
// Native macOS Settings window using an NSToolbar (via SettingsWindowController).
// Each tab maps to an existing section view — no content changes needed.

import SwiftUI
import AppKit

// MARK: - NativeSettingsView

/// Root view embedded in the Settings scene. Uses the standard macOS tab toolbar.
struct NativeSettingsView: View {
    @EnvironmentObject private var services: ServicesContainer
    @ObservedObject var tabSelection: SettingsWindowController.TabSelection

    var body: some View {
        Group {
            switch tabSelection.currentTab {
            case .general:
                ScrollView {
                    GeneralSection(
                        settings: services.settings,
                        hotkeyManager: services.hotkeyManager
                    )
                    .padding(20)
                }
            case .model:
                ModelSection(
                    settings: services.settings,
                    coordinator: services.coordinator
                )
            case .language:
                LanguageSection(settings: services.settings)
            case .engine:
                ScrollView {
                    EngineSection(settings: services.settings)
                        .padding(20)
                }
            case .permissions:
                ScrollView {
                    PermissionsSection(micManager: services.micPermManager)
                        .padding(20)
                }
            case .history:
                ScrollView {
                    HistoryView(historyService: services.historyService)
                        .padding(20)
                }
            case .about:
                ScrollView {
                    AboutSection()
                        .padding(20)
                }
            }
        }
        // Force the window to stay at a consistent size across tabs
        .frame(width: 560, height: 520)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tab enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, model, language, engine, permissions, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Général")
        case .model: return String(localized: "Modèle")
        case .language: return String(localized: "Langue")
        case .engine: return String(localized: "Moteur")
        case .permissions: return String(localized: "Permissions")
        case .history: return String(localized: "Historique")
        case .about: return String(localized: "À propos")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .model: return "cube.box.fill"
        case .language: return "globe"
        case .engine: return "cpu.fill"
        case .permissions: return "lock.shield.fill"
        case .history: return "clock.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - NSVisualEffectView wrapper (kept for potential reuse)

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
