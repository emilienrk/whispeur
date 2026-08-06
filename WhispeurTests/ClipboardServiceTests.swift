// ClipboardServiceTests.swift
// WhispeurTests

import AppKit
import Testing

@MainActor
struct ClipboardServiceTests {

    /// A throwaway named pasteboard, so tests never touch the user's own clipboard.
    private func makeService() -> (ClipboardService, NSPasteboard) {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.whispeur.tests.\(UUID().uuidString)"))
        return (ClipboardService(pasteboard: pb), pb)
    }

    @Test("Restoring puts the previous text back")
    func restoreBringsBackPreviousText() {
        let (service, pb) = makeService()
        pb.clearContents()
        pb.setString("what the user had copied", forType: .string)

        let snapshot = service.snapshotPasteboard()
        let changeCount = service.copyToClipboard("the transcription")
        #expect(pb.string(forType: .string) == "the transcription")

        service.restorePasteboard(snapshot, ifUnchangedSince: changeCount)

        #expect(pb.string(forType: .string) == "what the user had copied")
    }

    @Test("Snapshot keeps every type of an item")
    func snapshotPreservesAllTypes() {
        let (service, pb) = makeService()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data([0x01, 0x02]), forType: .tiff)
        pb.writeObjects([item])

        let snapshot = service.snapshotPasteboard()
        let changeCount = service.copyToClipboard("the transcription")
        service.restorePasteboard(snapshot, ifUnchangedSince: changeCount)

        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.data(forType: .tiff) == Data([0x01, 0x02]))
    }

    @Test("A write by someone else cancels the restore")
    func concurrentWriteCancelsRestore() {
        let (service, pb) = makeService()
        pb.clearContents()
        pb.setString("old", forType: .string)

        let snapshot = service.snapshotPasteboard()
        let changeCount = service.copyToClipboard("the transcription")

        // The user hits ⌘C on something else during the paste delay.
        pb.clearContents()
        pb.setString("just copied by the user", forType: .string)

        service.restorePasteboard(snapshot, ifUnchangedSince: changeCount)

        #expect(pb.string(forType: .string) == "just copied by the user")
    }

    @Test("An empty pasteboard is restored empty")
    func emptyPasteboardStaysEmpty() {
        let (service, pb) = makeService()
        pb.clearContents()

        let snapshot = service.snapshotPasteboard()
        let changeCount = service.copyToClipboard("the transcription")
        service.restorePasteboard(snapshot, ifUnchangedSince: changeCount)

        #expect(pb.string(forType: .string) == nil)
    }

    /// ⌘V with nothing editable focused only earns the macOS rejection beep.
    @Test("Nothing editable focused: the text is copied, never pasted")
    func notEditableFocusSkipsPaste() async {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.whispeur.tests.\(UUID().uuidString)"))
        let service = ClipboardService(
            pasteboard: pb,
            focusState: { .notEditable },
            notifyCopied: {}
        )

        let result = await service.copyAndPaste("the transcription")

        #expect(result == .copiedOnly)
        #expect(pb.string(forType: .string) == "the transcription")
    }
}
