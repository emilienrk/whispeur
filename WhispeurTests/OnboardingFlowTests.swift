// OnboardingFlowTests.swift
// WhispeurTests

import Testing

@MainActor
private final class FakeRequirements: OnboardingRequirements {
    var isMicrophoneGranted: Bool
    var isAccessibilityGranted: Bool
    var hasUsableModel: Bool

    init(mic: Bool = false, accessibility: Bool = false, model: Bool = false) {
        self.isMicrophoneGranted = mic
        self.isAccessibilityGranted = accessibility
        self.hasUsableModel = model
    }
}

@MainActor
struct OnboardingFlowTests {

    @Test("A fresh flow starts on the welcome step")
    func startsOnWelcome() {
        let flow = OnboardingFlow(requirements: FakeRequirements())
        #expect(flow.step == .welcome)
        #expect(flow.canAdvance == true)
    }

    @Test("Microphone blocks until it is granted")
    func microphoneIsBlocking() {
        let requirements = FakeRequirements()
        let flow = OnboardingFlow(requirements: requirements)

        flow.advance()
        #expect(flow.step == .microphone)
        #expect(flow.canAdvance == false)

        flow.advance()
        #expect(flow.step == .microphone)

        requirements.isMicrophoneGranted = true
        #expect(flow.canAdvance == true)
        flow.advance()
        #expect(flow.step == .accessibility)
    }

    @Test("Accessibility can be skipped: it only degrades auto-paste")
    func accessibilityIsOptional() {
        let requirements = FakeRequirements(mic: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()

        #expect(flow.step == .accessibility)
        #expect(flow.canAdvance == true)
        flow.advance()
        #expect(flow.step == .model)
    }

    @Test("Model blocks until one is downloaded")
    func modelIsBlocking() {
        let requirements = FakeRequirements(mic: true, accessibility: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()

        #expect(flow.step == .model)
        #expect(flow.canAdvance == false)
        flow.advance()
        #expect(flow.step == .model)

        requirements.hasUsableModel = true
        flow.advance()
        #expect(flow.step == .engineOverview)
    }

    @Test("Both engine steps explain rather than gate, so neither ever blocks")
    func engineStepsAreOptional() {
        let requirements = FakeRequirements(mic: true, accessibility: true, model: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()

        #expect(flow.step == .engineOverview)
        #expect(flow.canAdvance == true)
        flow.advance()

        #expect(flow.step == .engine)
        #expect(flow.canAdvance == true)
        flow.advance()
        #expect(flow.step == .hotkey)
    }

    @Test("Everything already granted lands on the engine overview, never past it")
    func satisfiedStepsAreSkipped() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        #expect(flow.step == .engineOverview)
    }

    @Test("Back walks the steps in reverse and stops at welcome")
    func backStopsAtWelcome() {
        let requirements = FakeRequirements(mic: true)
        let flow = OnboardingFlow(requirements: requirements)
        flow.advance()
        #expect(flow.step == .accessibility)

        flow.back()
        #expect(flow.step == .microphone)
        flow.back()
        #expect(flow.step == .welcome)
        flow.back()
        #expect(flow.step == .welcome)
    }

    @Test("Back does not re-skip a satisfied step, otherwise it would be a trap")
    func backIgnoresSatisfaction() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        #expect(flow.step == .engineOverview)

        flow.back()
        #expect(flow.step == .model)
    }

    @Test("Done is terminal")
    func doneIsTerminal() {
        let flow = OnboardingFlow(
            requirements: FakeRequirements(mic: true, accessibility: true, model: true)
        )
        flow.advance()
        flow.advance()
        flow.advance()
        flow.advance()
        #expect(flow.step == .done)
        #expect(flow.canAdvance == false)

        flow.advance()
        #expect(flow.step == .done)
    }
}
