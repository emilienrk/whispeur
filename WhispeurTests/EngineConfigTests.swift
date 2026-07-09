// EngineConfigTests.swift
// WhispeurTests

import Testing
import Foundation

@MainActor
struct EngineConfigTests {

    @Test("initialPrompt is persisted and flows into the engine config")
    func initialPromptMapping() {
        let s = AppSettings.shared
        let saved = s.initialPrompt
        defer { s.initialPrompt = saved }

        s.initialPrompt = "Whispeur, xcodegen, ggml"

        #expect(s.engineConfig.initialPrompt == "Whispeur, xcodegen, ggml")
        #expect(UserDefaults.standard.string(forKey: "initialPrompt") == "Whispeur, xcodegen, ggml")
    }

    @Test("engine config mirrors the existing engine settings")
    func existingSettingsMapping() {
        let s = AppSettings.shared
        let savedBeam = s.useBeamSearch
        let savedTemp = s.temperature
        defer {
            s.useBeamSearch = savedBeam
            s.temperature = savedTemp
        }

        s.useBeamSearch = true
        s.temperature = 0.3

        let config = s.engineConfig
        #expect(config.useBeamSearch == true)
        #expect(abs(config.temperature - 0.3) < 0.0001)
    }
}
