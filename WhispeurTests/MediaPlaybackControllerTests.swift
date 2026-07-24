// MediaPlaybackControllerTests.swift
// WhispeurTests

import Testing

@MainActor
private final class FakeAudioProbe: SystemAudioProbe {
    private var readings: [Bool]
    private var lastReading = false
    private(set) var readCount = 0

    init(_ readings: [Bool]) { self.readings = readings }

    var isOutputActive: Bool {
        readCount += 1
        // Bounded polling can outlast a fixed queue of readings; repeat the last
        // one instead of falling back to false, so "sound never stops" stays
        // deterministic across every poll.
        if !readings.isEmpty {
            lastReading = readings.removeFirst()
        }
        return lastReading
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
    enabled: Bool = true,
    pollInterval: Duration = .milliseconds(1),
    timeout: Duration = .milliseconds(50)
) -> (MediaPlaybackController, FakeAudioProbe, FakeMediaKeySender) {
    let probe = FakeAudioProbe(readings)
    let sender = FakeMediaKeySender()
    let controller = MediaPlaybackController(
        probe: probe,
        keySender: sender,
        isEnabled: { enabled },
        resumePollInterval: pollInterval,
        resumeTimeout: timeout
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
        // The resume gave up without proof the sound stopped, so the debt
        // stands — the next dictation must not blindly re-toggle the key.
        #expect(controller.didPause == true)
    }

    @Test("A standing resume debt stops the next dictation from re-toggling the key")
    func standingDebtPreventsBlindRetoggle() async {
        let (controller, _, sender) = makeController(readings: [true, true])
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        // Second dictation while the other source is still making noise: the
        // media is already paused by us, so the key must stay untouched.
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)
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

    @Test("A dictation starting mid-resume keeps the media paused and silences the stale resume")
    func newPauseDuringSettleKeepsMediaPaused() async {
        let (controller, _, sender) = makeController(
            readings: [true, false],
            pollInterval: .milliseconds(50)
        )
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        let settling = Task { await controller.resumeAfterRecording() }
        // didPause flips to false as the very first thing resumeAfterRecording
        // does, before it ever suspends — wait for that instead of assuming a
        // FIFO scheduling order between this task and the one above.
        while controller.didPause { await Task.yield() }

        // Second dictation starts before the resume finished settling.
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        await settling.value
        // The debt survived the stale resume — that's the behavior under test.
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)
    }
}
