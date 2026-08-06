// MediaPlaybackControllerTests.swift
// WhispeurTests

import Testing

private func player(_ pid: pid_t, _ bundleID: String = "com.spotify.client") -> AudioProcess {
    AudioProcess(pid: pid, bundleID: bundleID, isCapturingInput: false)
}

/// A call detected the way FaceTime is: playing and capturing at once.
private func call(_ pid: pid_t, _ bundleID: String = "com.apple.avconferenced") -> AudioProcess {
    AudioProcess(pid: pid, bundleID: bundleID, isCapturingInput: true)
}

@MainActor
private final class FakeProcessProbe: AudioProcessProbe {
    private var readings: [[AudioProcess]]
    private var lastReading: [AudioProcess] = []
    private(set) var readCount = 0

    init(_ readings: [[AudioProcess]]) { self.readings = readings }

    func outputtingProcesses() -> [AudioProcess] {
        readCount += 1
        if !readings.isEmpty { lastReading = readings.removeFirst() }
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
    readings: [[AudioProcess]],
    enabled: Bool = true
) -> (MediaPlaybackController, FakeProcessProbe, FakeMediaKeySender) {
    let probe = FakeProcessProbe(readings)
    let sender = FakeMediaKeySender()
    let controller = MediaPlaybackController(
        probe: probe,
        keySender: sender,
        isEnabled: { enabled },
        verifyDelay: .milliseconds(1)
    )
    return (controller, probe, sender)
}

@MainActor
struct MediaPlaybackControllerTests {

    // MARK: - Classification

    @Test("A process that plays and captures at once is a call, whatever its name")
    func simultaneousCaptureMeansCommunication() {
        #expect(classify(call(1, "com.unknown.newapp")) == .communication)
    }

    @Test("A listed communication bundle is a call even when it is not capturing")
    func listedBundleMeansCommunication() {
        #expect(classify(player(1, "com.apple.FaceTime")) == .communication)
    }

    @Test("A plain player, and one with no bundle ID, are players")
    func everythingElseIsAPlayer() {
        #expect(classify(player(1)) == .player)
        #expect(classify(AudioProcess(pid: 1, bundleID: nil, isCapturingInput: false)) == .player)
    }

    // MARK: - Ignored sources

    @Test("The system sound daemon is never a player: our own cues play under its PID")
    func systemSoundDaemonIsIgnored() {
        // AudioServicesPlayAlertSound renders the dictation cues out of process,
        // so they surface as a process that started mid-dictation and made the
        // controller undo the pause it had just made correctly.
        #expect(isIgnoredSource(bundleID: "systemsoundserverd", ownBundleID: "com.whispeur.app"))
    }

    @Test("A second Whispeur instance is ignored, a real player is not")
    func ownBundleIsIgnoredButPlayersAreNot() {
        #expect(isIgnoredSource(bundleID: "com.whispeur.app", ownBundleID: "com.whispeur.app"))
        #expect(!isIgnoredSource(bundleID: "com.spotify.client", ownBundleID: "com.whispeur.app"))
        #expect(!isIgnoredSource(bundleID: nil, ownBundleID: "com.whispeur.app"))
    }

    // MARK: - Pause decision

    @Test("Nothing playing: no media key is ever sent")
    func silentSystemSendsNothing() async {
        // The regression that started this: a player open but paused feeds no
        // output, so it must stay invisible and never be woken up.
        let (controller, _, sender) = makeController(readings: [[]])
        controller.pauseForRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 0)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 0)
    }

    @Test("A call in progress: nothing is touched at all")
    func callIsLeftAlone() async {
        let (controller, _, sender) = makeController(readings: [[call(42)]])
        controller.pauseForRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 0)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 0)
    }

    @Test("A call alongside music: the call wins, the music keeps playing")
    func callWinsOverMusic() async {
        let (controller, _, sender) = makeController(readings: [[player(10), call(42)]])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(controller.didPause == false)
        #expect(sender.sendCount == 0)
    }

    @Test("Music playing: pause then resume")
    func musicIsPausedAndResumed() async {
        let (controller, _, sender) = makeController(readings: [[player(10)], [player(10)]])
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(controller.didPause == false)
        #expect(sender.sendCount == 2)
    }

    @Test("A player whose audio unit lingers after the pause is still resumed")
    func lingeringOutputStillResumes() async {
        // Spotify keeps its output running for seconds after a pause. Demanding
        // proof of silence would strand the music paused forever.
        let (controller, _, sender) = makeController(readings: [[player(10)], [player(10)]])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(sender.sendCount == 2)
    }

    // MARK: - Self-correction

    @Test("The key woke a paused player instead: the toggle is undone and no resume follows")
    func spuriousStartIsUndone() async {
        // The browser was playing, but the key was routed to a paused Spotify,
        // which starts. pid 99 was silent before and is playing now.
        let (controller, _, sender) = makeController(
            readings: [[player(10, "com.google.Chrome")], [player(10, "com.google.Chrome"), player(99)]]
        )
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        // One key to pause, one to undo — and no third key on resume.
        #expect(sender.sendCount == 2)
        #expect(controller.didPause == false)
    }

    @Test("The same processes playing after the key does not count as a spurious start")
    func unchangedProcessesAreNotASpuriousStart() async {
        let (controller, _, sender) = makeController(readings: [[player(10)], [player(10)]])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(sender.sendCount == 2)
    }

    // MARK: - Guards

    @Test("Setting disabled: the probe is never even read")
    func disabledSettingIsInert() async {
        let (controller, probe, sender) = makeController(readings: [[player(10)]], enabled: false)
        controller.pauseForRecording()
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
        #expect(controller.didPause == false)
    }

    @Test("Resume called twice sends a single play key")
    func doubleResumeIsIdempotent() async {
        let (controller, _, sender) = makeController(readings: [[player(10)], [player(10)]])
        controller.pauseForRecording()
        await controller.resumeAfterRecording()
        await controller.resumeAfterRecording()

        #expect(sender.sendCount == 2)
    }

    @Test("Resume without a preceding pause does nothing")
    func resumeWithoutPauseIsNoOp() async {
        let (controller, probe, sender) = makeController(readings: [[]])
        await controller.resumeAfterRecording()

        #expect(probe.readCount == 0)
        #expect(sender.sendCount == 0)
    }

    @Test("A dictation starting while a pause is owed does not re-toggle the key")
    func standingDebtPreventsBlindRetoggle() async {
        let (controller, _, sender) = makeController(readings: [[player(10)], [player(10)]])
        controller.pauseForRecording()
        #expect(sender.sendCount == 1)

        // Second dictation before any resume ran: the media is already paused by
        // us, so the key must stay untouched or it would start the music.
        controller.pauseForRecording()
        #expect(controller.didPause == true)
        #expect(sender.sendCount == 1)

        await controller.resumeAfterRecording()
        #expect(sender.sendCount == 2)
    }
}
