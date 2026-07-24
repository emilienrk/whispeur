// MediaPlaybackControllerTests.swift
// WhispeurTests

import Testing

@MainActor
private final class FakeAudioProbe: SystemAudioProbe {
    private var readings: [Bool]
    private(set) var readCount = 0

    init(_ readings: [Bool]) { self.readings = readings }

    var isOutputActive: Bool {
        readCount += 1
        return readings.isEmpty ? false : readings.removeFirst()
    }
}

@MainActor
private final class FakeMediaKeySender: MediaKeySender {
    private(set) var sendCount = 0
    func sendPlayPause() { sendCount += 1 }
}

@MainActor
private func makeController(
    readings: [Bool],
    enabled: Bool = true
) -> (MediaPlaybackController, FakeAudioProbe, FakeMediaKeySender) {
    let probe = FakeAudioProbe(readings)
    let sender = FakeMediaKeySender()
    let controller = MediaPlaybackController(
        probe: probe,
        keySender: sender,
        isEnabled: { enabled },
        resumeSettleDelay: .zero
    )
    return (controller, probe, sender)
}

@MainActor
struct MediaPlaybackControllerTests {

    @Test("Nothing playing: no media key is ever sent")
    func silentSystemSendsNothing() async {
        let (controller, _, sender) = makeController(readings: [false])
        controller.pauseForRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 0)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 0)
    }

    @Test("Music playing then silent: pause then resume")
    func musicIsPausedAndResumed() async {
        let (controller, _, sender) = makeController(readings: [true, false])
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 2)
    }

    @Test("Zoom call: sound never stopped, so no resume key is sent")
    func stillPlayingAtResumeSendsNoPlay() async {
        let (controller, _, sender) = makeController(readings: [true, true])
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 1)
        #expect(controller.didPause == false)
    }

    @Test("Setting disabled: the probe is never even read")
    func disabledSettingIsInert() async {
        let (controller, probe, sender) = makeController(readings: [true, false], enabled: false)
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
        #expect(controller.didPause == false)
    }

    @Test("Resume called twice sends a single play key")
    func doubleResumeIsIdempotent() async {
        let (controller, _, sender) = makeController(readings: [true, false, false])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()
        await controller.resumeAfterRecording()

        #expect(sender.sendCount == 2)
    }

    @Test("Resume without a preceding pause does nothing")
    func resumeWithoutPauseIsNoOp() async {
        let (controller, probe, sender) = makeController(readings: [false])
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
    }
}
