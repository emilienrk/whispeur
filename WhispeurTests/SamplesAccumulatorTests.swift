// SamplesAccumulatorTests.swift
// WhispeurTests

import Testing

struct SamplesAccumulatorTests {

    @Test("Reading the count leaves the samples untouched")
    func countDoesNotDrain() {
        let accumulator = SamplesAccumulator()
        accumulator.append([0.1, 0.2, 0.3])

        // A live waveform would poll this on every frame.
        #expect(accumulator.count == 3)
        #expect(accumulator.count == 3)

        #expect(accumulator.drainAll() == [0.1, 0.2, 0.3])
    }

    @Test("Draining empties the buffer")
    func drainEmptiesBuffer() {
        let accumulator = SamplesAccumulator()
        accumulator.append([0.1, 0.2])

        #expect(accumulator.drainAll() == [0.1, 0.2])
        #expect(accumulator.count == 0)
        #expect(accumulator.drainAll().isEmpty)
    }

    @Test("Appends accumulate in order")
    func appendsKeepOrder() {
        let accumulator = SamplesAccumulator()
        accumulator.append([0.1])
        accumulator.append([0.2, 0.3])

        #expect(accumulator.count == 3)
        #expect(accumulator.drainAll() == [0.1, 0.2, 0.3])
    }
}
