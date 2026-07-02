// SettingsView.swift
// Whispeur
//
// Native macOS Settings window using SwiftUI's TabView.
// Each tab maps to an existing section view — no content changes needed.

import SwiftUI
import AppKit

// MARK: - NativeSettingsView

/// Root view embedded in the Settings scene. Uses the standard macOS tab toolbar.
struct NativeSettingsView: View {
    @EnvironmentObject private var services: ServicesContainer

    var body: some View {
        TabView {
            ScrollView {
                GeneralSection(
                    settings: services.settings,
                    hotkeyManager: services.hotkeyManager
                )
                .padding(20)
            }
            .tabItem {
                Label("Général", systemImage: "gearshape.fill")
            }
            .tag(SettingsTab.general)

            ScrollView {
                ModelSection(
                    settings: services.settings,
                    coordinator: services.coordinator
                )
                .padding(20)
            }
            .tabItem {
                Label("Modèle", systemImage: "cube.box.fill")
            }
            .tag(SettingsTab.model)

            ScrollView {
                LanguageSection(settings: services.settings)
                    .padding(20)
            }
            .tabItem {
                Label("Langue", systemImage: "globe")
            }
            .tag(SettingsTab.language)

            ScrollView {
                EngineSection(settings: services.settings)
                    .padding(20)
            }
            .tabItem {
                Label("Moteur", systemImage: "cpu.fill")
            }
            .tag(SettingsTab.engine)

            ScrollView {
                PermissionsSection(micManager: services.micPermManager)
                    .padding(20)
            }
            .tabItem {
                Label("Permissions", systemImage: "lock.shield.fill")
            }
            .tag(SettingsTab.permissions)

            ScrollView {
                HistoryView(historyService: services.historyService)
                    .padding(20)
            }
            .tabItem {
                Label("Historique", systemImage: "clock.fill")
            }
            .tag(SettingsTab.history)
        }
        .frame(width: 560, height: 520)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tab enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, model, language, engine, permissions, history
    var id: String { rawValue }
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
