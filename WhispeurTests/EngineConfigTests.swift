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

    @Test("VAD disabled produces nil model path")
    func vadDisabledNilPath() {
        let s = AppSettings.shared
        let saved = s.vadEnabled
        defer { s.vadEnabled = saved }

        s.vadEnabled = false

        #expect(s.engineConfig.vadEnabled == false)
        #expect(s.engineConfig.vadModelPath == nil)
    }

    @Test("VAD enabled resolves the path only when the model file exists")
    func vadEnabledPathResolution() {
        let s = AppSettings.shared
        let saved = s.vadEnabled
        defer { s.vadEnabled = saved }

        s.vadEnabled = true
        let model = WhisperModelDescriptor.vadSilero

        if model.isDownloaded {
            #expect(s.engineConfig.vadModelPath == model.localURL.path(percentEncoded: false))
        } else {
            #expect(s.engineConfig.vadModelPath == nil)
        }
    }
}
