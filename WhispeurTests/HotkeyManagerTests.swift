// HotkeyManagerTests.swift
// WhispeurTests
//
// Tests de la logique d'interception du CGEventTap (handleRawEvent)
// via des CGEvents synthétiques — aucun tap réel n'est installé.

import Testing
import AppKit
import CoreGraphics

@MainActor
struct HotkeyManagerTests {

    private func keyEvent(_ keyCode: Int, down: Bool, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: down
        )!
        event.flags = flags
        return event
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { cont.resume() }
        }
    }

    // MARK: - Bug 1 : espace seule cassée quand ⌥Espace est bindé

    @Test("Espace seule traverse le tap quand ⌥Espace est bindé (pas d'enregistrement en cours)")
    func plainSpacePassesThroughWhenComboBound() {
        let manager = HotkeyManager()
        manager.updateHotKey(HotKey(keyCode: 49, modifiers: Int(CGEventFlags.maskAlternate.rawValue)))

        let down = manager.handleRawEvent(type: .keyDown, event: keyEvent(49, down: true))
        let up   = manager.handleRawEvent(type: .keyUp,   event: keyEvent(49, down: false))

        #expect(down != nil, "keyDown espace seule ne doit pas être consommé")
        #expect(up != nil, "keyUp espace seule ne doit pas être consommé")
    }

    @Test("Le keyUp anti-blocage n'est avalé que si un appui du raccourci est engagé")
    func unstickReleaseOnlyWhenEngaged() {
        let manager = HotkeyManager()
        manager.updateHotKey(HotKey(keyCode: 49, modifiers: Int(CGEventFlags.maskAlternate.rawValue)))

        // ⌥Espace enfoncé → consommé, appui engagé.
        let down = manager.handleRawEvent(type: .keyDown, event: keyEvent(49, down: true, flags: .maskAlternate))
        #expect(down == nil)

        // ⌥ relâchée avant Espace : le keyUp d'Espace (sans modif) doit être
        // consommé pour terminer l'enregistrement (anti-blocage).
        let unstick = manager.handleRawEvent(type: .keyUp, event: keyEvent(49, down: false))
        #expect(unstick == nil)

        // Appui suivant d'Espace seule : plus rien d'engagé → doit traverser.
        let later = manager.handleRawEvent(type: .keyUp, event: keyEvent(49, down: false))
        #expect(later != nil)
    }

    // MARK: - Bug 2/3 : touche dictée 🎤 (keycode 176)

    @Test("Le raccourci par défaut est la touche dictée (176), pas Mission Control (160)")
    func defaultHotKeyIsDictationKey() {
        #expect(HotKey.defaultHotKey.keyCode == 176)
        #expect(HotKey.defaultHotKey.modifiers == 0)
        #expect(HotKey.defaultHotKey.displayString.contains("Dictée"))
    }

    @Test("La touche dictée bindée est consommée (la dictée Apple ne doit pas la recevoir)")
    func dictationKeyConsumedWhenBound() {
        let manager = HotkeyManager()
        manager.updateHotKey(.defaultHotKey)

        let down = manager.handleRawEvent(type: .keyDown, event: keyEvent(176, down: true))
        let up   = manager.handleRawEvent(type: .keyUp,   event: keyEvent(176, down: false))

        #expect(down == nil, "keyDown 🎤 doit être consommé")
        #expect(up == nil, "keyUp 🎤 doit être consommé")
    }

    // MARK: - Répétition automatique en mode Basculer

    @Test("Les répétitions auto du raccourci ne re-déclenchent pas (mode Basculer)")
    func autorepeatDoesNotRetrigger() async {
        let manager = HotkeyManager()
        manager.updateHotKey(HotKey(keyCode: 49, modifiers: 0))
        manager.setMode(.toggle)

        let counter = Counter()
        manager.onKeyDown = { counter.downs += 1 }
        manager.onKeyUp   = { counter.ups += 1 }

        _ = manager.handleRawEvent(type: .keyDown, event: keyEvent(49, down: true))

        let repeatEvent = keyEvent(49, down: true)
        repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let r1 = manager.handleRawEvent(type: .keyDown, event: repeatEvent)
        let r2 = manager.handleRawEvent(type: .keyDown, event: repeatEvent)

        await drainMainQueue()

        #expect(r1 == nil && r2 == nil, "les répétitions du raccourci restent consommées")
        #expect(counter.downs == 1, "un seul déclenchement malgré les répétitions")
        #expect(counter.ups == 0, "le toggle ne doit pas s'arrêter sur une répétition")
    }

    // MARK: - Capture d'un nouveau raccourci via le tap

    @Test("La capture attrape une combinaison touche+modificateurs et consomme l'événement")
    func captureGrabsComboAndConsumes() async {
        let manager = HotkeyManager()
        let box = CapturedBox()

        manager.beginHotKeyCapture { box.value = $0; box.called = true }
        let result = manager.handleRawEvent(type: .keyDown, event: keyEvent(49, down: true, flags: .maskAlternate))

        await drainMainQueue()

        #expect(result == nil, "l'événement capturé doit être consommé")
        #expect(box.called)
        #expect(box.value == HotKey(keyCode: 49, modifiers: Int(CGEventFlags.maskAlternate.rawValue)))
    }

    @Test("Échap annule la capture")
    func escapeCancelsCapture() async {
        let manager = HotkeyManager()
        let box = CapturedBox()

        manager.beginHotKeyCapture { box.value = $0; box.called = true }
        let result = manager.handleRawEvent(type: .keyDown, event: keyEvent(53, down: true))

        await drainMainQueue()

        #expect(result == nil)
        #expect(box.called)
        #expect(box.value == nil)
    }

    @Test("Un modificateur seul se capture à son relâchement")
    func captureLoneModifierOnRelease() async {
        let manager = HotkeyManager()
        let box = CapturedBox()

        manager.beginHotKeyCapture { box.value = $0; box.called = true }

        // fn (63) enfoncée puis relâchée.
        let fnDown = keyEvent(63, down: true)
        fnDown.flags = .maskSecondaryFn
        let downResult = manager.handleRawEvent(type: .flagsChanged, event: fnDown)
        #expect(downResult == nil)

        let fnUp = keyEvent(63, down: false)
        fnUp.flags = []
        let upResult = manager.handleRawEvent(type: .flagsChanged, event: fnUp)

        await drainMainQueue()

        #expect(upResult == nil)
        #expect(box.called)
        #expect(box.value == HotKey(keyCode: 63, modifiers: 0))
    }

    @Test("Pendant la capture, l'ancien raccourci ne déclenche pas d'enregistrement")
    func oldHotkeyDoesNotFireDuringCapture() async {
        let manager = HotkeyManager()
        manager.updateHotKey(HotKey(keyCode: 49, modifiers: 0))

        let counter = Counter()
        manager.onKeyDown = { counter.downs += 1 }

        let box = CapturedBox()
        manager.beginHotKeyCapture { box.value = $0; box.called = true }

        _ = manager.handleRawEvent(type: .keyDown, event: keyEvent(49, down: true))
        await drainMainQueue()

        #expect(counter.downs == 0, "la touche doit être capturée, pas déclenchée")
        #expect(box.value == HotKey(keyCode: 49, modifiers: 0))
    }
}

// MARK: - Helpers

@MainActor
private final class Counter {
    var downs = 0
    var ups = 0
}

@MainActor
private final class CapturedBox {
    var value: HotKey?
    var called = false
}
