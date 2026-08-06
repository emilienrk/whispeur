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

    @Test("pauseMediaWhileRecording round-trips through UserDefaults")
    func pauseMediaWhileRecordingPersists() {
        let s = AppSettings.shared
        let saved = s.pauseMediaWhileRecording
        defer { s.pauseMediaWhileRecording = saved }

        s.pauseMediaWhileRecording = false
        #expect(s.pauseMediaWhileRecording == false)
        #expect(UserDefaults.standard.bool(forKey: "pauseMediaWhileRecording") == false)

        s.pauseMediaWhileRecording = true
        #expect(s.pauseMediaWhileRecording == true)
        #expect(UserDefaults.standard.bool(forKey: "pauseMediaWhileRecording") == true)
    }

    @Test("a non-empty prompt is carried to every decode window")
    func promptIsCarried() {
        let prompt = strdup("Whispeur, xcodegen, ggml")
        defer { free(prompt) }

        var config = WhisperEngineConfig.default
        config.initialPrompt = "Whispeur, xcodegen, ggml"

        let params = WhisperService.makeParams(
            config: config,
            maxThreads: 4,
            strategy: WHISPER_SAMPLING_GREEDY,
            cLanguage: nil,
            cPrompt: UnsafePointer(prompt),
            cVadPath: nil
        )

        #expect(params.initial_prompt != nil)
        #expect(params.carry_initial_prompt == true)
    }

    @Test("each preset stands alone within the prompt budget")
    func presetsFitTheBudget() {
        #expect(PromptPreset.all.isEmpty == false)

        for preset in PromptPreset.all {
            #expect(preset.text.isEmpty == false)
            #expect(preset.text.count <= PromptPreset.approximateCharacterBudget)
        }

        let titles = Set(PromptPreset.all.map(\.id))
        #expect(titles.count == PromptPreset.all.count)
    }

    @Test("an empty prompt leaves carry_initial_prompt off")
    func emptyPromptIsNotCarried() {
        let params = WhisperService.makeParams(
            config: .default,
            maxThreads: 4,
            strategy: WHISPER_SAMPLING_GREEDY,
            cLanguage: nil,
            cPrompt: nil,
            cVadPath: nil
        )

        #expect(params.initial_prompt == nil)
        #expect(params.carry_initial_prompt == false)
    }

    @Test("hasCompletedOnboarding round-trips through UserDefaults")
    func onboardingFlagPersists() {
        let s = AppSettings.shared
        let saved = s.hasCompletedOnboarding
        defer { s.hasCompletedOnboarding = saved }

        s.hasCompletedOnboarding = true
        #expect(s.hasCompletedOnboarding == true)
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == true)

        s.hasCompletedOnboarding = false
        #expect(s.hasCompletedOnboarding == false)
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == false)
    }
}
