// WhisperModelFamilyTests.swift
// WhispeurTests

import Testing

struct WhisperModelFamilyTests {

    @Test("Quantization suffix and the English marker fold into the base name")
    func familyNameStripsVariantMarkers() {
        func family(_ name: String) -> String {
            WhisperModelDescriptor.catalog.first { $0.name == name }!.familyName
        }

        #expect(family("tiny") == "tiny")
        #expect(family("tiny-q5_1") == "tiny")
        #expect(family("tiny.en-q8_0") == "tiny")
        #expect(family("large-v3-turbo-q5_0") == "large-v3-turbo")
        #expect(family("large-v2-q5_0") == "large-v2")
        #expect(family("large-v1") == "large-v1")
    }

    @Test("Every catalog model lands in exactly one family")
    func familiesCoverTheCatalog() {
        let grouped = WhisperModelDescriptor.families.flatMap(\.variants)

        #expect(grouped.count == WhisperModelDescriptor.catalog.count)
        #expect(Set(grouped.map(\.filename)) == Set(WhisperModelDescriptor.catalog.map(\.filename)))
    }

    @Test("Families keep catalog order, English-only variants last within each")
    func familyOrdering() {
        let names = WhisperModelDescriptor.families.map(\.name)
        #expect(names.first == "tiny")
        #expect(names.last == "large-v3-turbo")
        #expect(names.count == Set(names).count)

        for family in WhisperModelDescriptor.families {
            guard let firstEnglish = family.variants.firstIndex(where: \.isEnglishOnly) else { continue }
            let tail = family.variants[firstEnglish...].allSatisfy { $0.isEnglishOnly }
            #expect(tail, "\(family.name) mixes multilingual variants after English-only ones")
        }
    }

    @Test("sizeInfo splits into a precision and a file size")
    func sizeInfoParts() {
        let model = WhisperModelDescriptor.catalog.first { $0.name == "small-q5_1" }!

        #expect(model.quantization == "Q5_1")
        #expect(model.fileSize == "181 MiB")
        // The VAD model carries no precision marker.
        #expect(WhisperModelDescriptor.vadSilero.quantization.isEmpty)
        #expect(WhisperModelDescriptor.vadSilero.fileSize == "~1 MiB")
    }
}
