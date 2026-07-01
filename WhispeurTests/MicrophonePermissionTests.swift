// MicrophonePermissionTests.swift
// WhispeurTests

import Testing
import AVFoundation

struct MicrophonePermissionTests {

    @Test("MicrophonePermissionStatus: canRecord only when granted")
    @MainActor
    func canRecordOnlyWhenGranted() async {
        let manager = MicrophonePermissionManager()
        // In a sandboxed CI environment the status will be .denied or .undetermined.
        // We verify the invariant: canRecord ↔ status == .granted.
        let expected = manager.status == .granted
        #expect(manager.canRecord == expected)
    }

    @Test("currentStatus maps AVAuthorizationStatus correctly (smoke test)")
    @MainActor
    func currentStatusDoesNotCrash() {
        // Just verify the static mapping doesn't crash; actual value depends on the
        // test host's privacy settings.
        let status = MicrophonePermissionManager.currentStatus()
        let validStatuses: [MicrophonePermissionStatus] = [.undetermined, .granted, .denied, .restricted]
        #expect(validStatuses.contains(status))
    }
}
