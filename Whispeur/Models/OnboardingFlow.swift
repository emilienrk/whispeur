// OnboardingFlow.swift
// Whispeur
//
// Step sequencing for the first-launch setup.
//
// No UI and no system call live here: what macOS actually grants comes in
// through the injected requirements, so the whole progression is testable
// without permissions, downloads or a window.

import Foundation
import ApplicationServices

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case welcome
    case microphone
    case accessibility
    case model
    case engineOverview
    case engine
    case hotkey
    case done

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Injected dependency

@MainActor
protocol OnboardingRequirements {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    var hasUsableModel: Bool { get }
}

// MARK: - Flow

@MainActor
@Observable
final class OnboardingFlow {

    private(set) var step: OnboardingStep = .welcome

    private let requirements: any OnboardingRequirements

    init(requirements: any OnboardingRequirements) {
        self.requirements = requirements
    }

    /// Microphone and model are blocking: without them Whispeur cannot dictate
    /// at all. Accessibility only degrades auto-paste to a clipboard copy, so
    /// refusing it must not trap the user on that page.
    var canAdvance: Bool {
        switch step {
        case .welcome, .accessibility, .engineOverview, .engine, .hotkey: return true
        case .microphone: return requirements.isMicrophoneGranted
        case .model:      return requirements.hasUsableModel
        case .done:       return false
        }
    }

    func advance() {
        guard canAdvance, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        skipSatisfiedSteps()
    }

    /// Deliberately does not skip: a reinstall would otherwise bounce the user
    /// straight back forward, making the Back button look broken.
    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Someone reinstalling should not be walked through permissions they have
    /// already given.
    private func skipSatisfiedSteps() {
        while isSatisfied(step), let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    /// Engine settings are never "satisfied": they teach rather than gate, so the
    /// step is shown even to someone whose permissions and model are already there.
    private func isSatisfied(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone:    return requirements.isMicrophoneGranted
        case .accessibility: return requirements.isAccessibilityGranted
        case .model:         return requirements.hasUsableModel
        case .welcome, .engineOverview, .engine, .hotkey, .done: return false
        }
    }
}

// MARK: - Real requirements

@MainActor
struct SystemOnboardingRequirements: OnboardingRequirements {
    let micManager: MicrophonePermissionManager
    let settings: AppSettings

    var isMicrophoneGranted: Bool { micManager.canRecord }

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// The selected model specifically — having *some* model on disk is not
    /// enough, the pipeline loads the selected one.
    var hasUsableModel: Bool { settings.selectedModelDescriptor?.isDownloaded ?? false }
}
