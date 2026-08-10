// PipelineStateTests.swift
// WhispeurTests

import Testing
import Observation

struct PipelineStateTests {

    @Test("isActive is false for idle and error states")
    func isActiveReturnsFalseForTerminalStates() {
        #expect(PipelineState.idle.isActive == false)
        #expect(PipelineState.error("oops").isActive == false)
    }

    @Test("isActive is true for in-flight states")
    func isActiveReturnsTrueForInFlightStates() {
        #expect(PipelineState.loadingModel.isActive == true)
        #expect(PipelineState.recording.isActive == true)
        #expect(PipelineState.transcribing.isActive == true)
        #expect(PipelineState.pasting.isActive == true)
    }

    @Test("Equatable: same cases are equal")
    func equatableBasicCases() {
        #expect(PipelineState.idle == .idle)
        #expect(PipelineState.recording == .recording)
    }

    @Test("Equatable: error cases compare message")
    func equatableErrorCompareMessage() {
        #expect(PipelineState.error("msg") == .error("msg"))
        #expect(PipelineState.error("a") != .error("b"))
    }

    /// The menu bar icon is driven by `Observations` over `pipelineState`, which
    /// only works if the sequence hands over the current value before the
    /// changes — otherwise the icon would stay blank until the first dictation.
    @Test("Observations yields the current state, then each transition")
    @MainActor
    func observationsDeliverInitialValueThenChanges() async {
        let holder = StateHolder()
        var iterator = Observations({ holder.state }).makeAsyncIterator()

        #expect(await iterator.next() == .idle)

        holder.state = .recording
        #expect(await iterator.next() == .recording)

        holder.state = .transcribing
        #expect(await iterator.next() == .transcribing)
    }
}

/// Stands in for RecordingCoordinator: same shape, none of its services.
@MainActor
@Observable
private final class StateHolder {
    var state: PipelineState = .idle
}
