// PromptPreset.swift
// Whispeur
//
// Ready-made contents for the "Vocabulaire & style" field.
//
// Whisper conditions on the prompt as if it were previously transcribed text, so a
// preset must *demonstrate* the wanted vocabulary and punctuation — never instruct.
// Presets are meant to be combined, hence the shared token budget below.

import Foundation

struct PromptPreset: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let subtitle: String
    let text: String

    /// whisper.cpp keeps at most whisper_n_text_ctx/2 tokens (224) and drops the rest
    /// from the left. Roughly 4 characters per token in French, kept as a UI-side
    /// approximation only — the real tokenizer needs a loaded model.
    static let approximateCharacterBudget = 224 * 4

    static let all: [PromptPreset] = [
        PromptPreset(
            title: "Dev & outils",
            subtitle: "Noms de projets, CLI, jargon technique",
            text: "Whispeur, xcodegen, Sparkle, whisper.cpp, ggml, nix-darwin, OrbStack, pnpm, Swift, SwiftUI, Xcode, GitHub, pull request, commit, rebase, refactor, endpoint, build, runtime."
        ),
        PromptPreset(
            title: "Ponctuation soignée",
            subtitle: "Phrases complètes, virgules, majuscules",
            text: "Voici comment je veux que le texte sorte : des phrases complètes, avec des majuscules en début de phrase, des virgules là où il faut respirer, et un point à la fin. Les questions se terminent par un point d'interrogation."
        ),
        PromptPreset(
            title: "Minuscules, sans ponctuation",
            subtitle: "Style messagerie ou message de commit",
            text: "voilà comment je veux que ça sorte tout en minuscules sans ponctuation ni majuscules juste le texte au fil de la parole comme dans un message rapide"
        ),
        PromptPreset(
            title: "Français soutenu",
            subtitle: "Registre écrit, pour mails et courriers",
            text: "Je vous remercie de votre retour. Vous trouverez ci-joint le document demandé ; je reste à votre disposition pour tout complément d'information. Bien cordialement."
        ),
        PromptPreset(
            title: "Franglais tech",
            subtitle: "Ancre les termes anglais dans du français",
            text: "J'ai ouvert une pull request sur le repo, le build passe mais il reste deux tests flaky. On merge après review, puis je déploie en staging et je check les logs."
        )
    ]
}
