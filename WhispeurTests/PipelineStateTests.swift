// PipelineStateTests.swift
// WhispeurTests

import Testing

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
}
