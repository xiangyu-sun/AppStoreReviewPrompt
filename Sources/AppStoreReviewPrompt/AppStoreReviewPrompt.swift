import StoreKit
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The default review requester used when no custom one is injected.
///
/// - On iOS: calls `AppStore.requestReview(in:)` with the active `UIWindowScene`.
/// - On macOS: calls `AppStore.requestReview(in:)` with the key window's content view controller.
///
/// In a **SwiftUI** app you should inject the `@Environment(\.requestReview)` action instead:
/// ```swift
/// @Environment(\.requestReview) private var requestReview
/// let prompt = AppStoreReviewPrompt(configuration: config, reviewRequester: { requestReview() })
/// ```
@MainActor
private func defaultReviewRequester() {
    #if os(iOS)
    if let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
        AppStore.requestReview(in: scene)
    }
    #elseif os(macOS)
    if let viewController = NSApplication.shared.keyWindow?.contentViewController {
        AppStore.requestReview(in: viewController)
    }
    #endif
}

public struct ReviewPromoConfiguration: Sendable {
    public let appID: String
    public let promoteOnTime: Int

    public init(appID: String, promoteOnTime: Int) {
        self.appID = appID
        self.promoteOnTime = promoteOnTime
    }
}

private enum UserDefaultsKeys {
    static let processCompletedCount = "processCompletedCountKey"
    static let lastVersionPromptedForReview = "lastVersionPromptedForReviewKey"
    /// Stores a JSON-encoded array of `TimeInterval` values (dates as `timeIntervalSinceReferenceDate`)
    /// representing each time the review prompt was fired. Capped at 3 entries.
    static let promptDates = "reviewPromptDatesKey"
}

/// Abstracts `Date` creation so tests can inject a fixed clock.
public protocol DateProviding: Sendable {
    var now: Date { get }
}

/// Production implementation that returns the real current date.
public struct SystemDateProvider: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

public enum AppStoreReviewPromptError: Error, CustomDebugStringConvertible, Sendable {
    case currentVersionNotFound
    case reviewURLNotValid

    public var debugDescription: String {
        switch self {
        case .currentVersionNotFound:
            "Expected to find a bundle version in the info dictionary"
        case .reviewURLNotValid:
            "Expected a valid review URL"
        }
    }
}

/// Abstracts `Bundle` so tests can inject a version string without subclassing.
public protocol BundleProviding: Sendable {
    var bundleVersion: String? { get }
}

extension Bundle: BundleProviding {
    public var bundleVersion: String? {
        object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
    }
}

@MainActor
public final class AppStoreReviewPrompt: Sendable {

    /// Maximum number of times the OS will show the prompt within a rolling 365-day window.
    private static let maxPromptsPerYear = 3
    /// Minimum calendar days between consecutive prompts.
    private static let minDaysBetweenPrompts: Double = 60

    public let configuration: ReviewPromoConfiguration
    private let userDefaults: UserDefaults
    private let bundleProvider: any BundleProviding
    private let reviewRequester: @MainActor () -> Void
    private let dateProvider: any DateProviding

    public init(
        configuration: ReviewPromoConfiguration,
        userDefaults: UserDefaults = .standard,
        bundle: any BundleProviding = Bundle.main,
        dateProvider: any DateProviding = SystemDateProvider(),
        reviewRequester: (@MainActor () -> Void)? = nil
    ) {
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.bundleProvider = bundle
        self.dateProvider = dateProvider
        self.reviewRequester = reviewRequester ?? { defaultReviewRequester() }
    }

    /// Increments the process-completion counter and requests a review when all
    /// of the following conditions are met:
    ///
    /// - The completion count has reached `configuration.promoteOnTime`.
    /// - The current app version has not been prompted before.
    /// - Fewer than 3 prompts have been shown in the last 365 days (mirrors the OS cap).
    /// - At least 60 days have elapsed since the most recent prompt.
    ///
    /// On iOS the review dialog is presented in the active `UIWindowScene` via
    /// `AppStore.requestReview(in:)`. On macOS it is presented via the key
    /// window's content view controller using `AppStore.requestReview(in:)`.
    public func checkReviewRequest() throws {
        var count = userDefaults.integer(forKey: UserDefaultsKeys.processCompletedCount)
        count += 1
        userDefaults.set(count, forKey: UserDefaultsKeys.processCompletedCount)

        guard let currentVersion = bundleProvider.bundleVersion else {
            throw AppStoreReviewPromptError.currentVersionNotFound
        }

        let lastVersionPrompted = userDefaults.string(forKey: UserDefaultsKeys.lastVersionPromptedForReview)

        guard count >= configuration.promoteOnTime, currentVersion != lastVersionPrompted else {
            return
        }

        guard canPrompt(now: dateProvider.now) else {
            return
        }

        userDefaults.set(currentVersion, forKey: UserDefaultsKeys.lastVersionPromptedForReview)
        recordPrompt(date: dateProvider.now)
        reviewRequester()
    }

    // MARK: - Rate-limit helpers

    /// Returns `true` when the prompt is allowed based on the rolling-year cap and minimum gap.
    private func canPrompt(now: Date) -> Bool {
        let dates = storedPromptDates()
        let windowStart = now.addingTimeInterval(-365 * 24 * 3600)

        // Drop dates outside the 365-day window.
        let recentDates = dates.filter { $0 > windowStart }

        // Enforce OS cap: no more than 3 prompts per year.
        guard recentDates.count < Self.maxPromptsPerYear else {
            return false
        }

        // Enforce minimum spacing between prompts.
        if let lastPrompt = recentDates.max() {
            let daysSinceLast = now.timeIntervalSince(lastPrompt) / (24 * 3600)
            guard daysSinceLast >= Self.minDaysBetweenPrompts else {
                return false
            }
        }

        return true
    }

    /// Appends `date` to the stored list, keeping only the most recent `maxPromptsPerYear` entries.
    private func recordPrompt(date: Date) {
        var dates = storedPromptDates()
        dates.append(date)
        // Keep only the newest entries so storage stays bounded.
        if dates.count > Self.maxPromptsPerYear {
            dates = Array(dates.sorted().suffix(Self.maxPromptsPerYear))
        }
        let intervals = dates.map { $0.timeIntervalSinceReferenceDate }
        userDefaults.set(intervals, forKey: UserDefaultsKeys.promptDates)
    }

    private func storedPromptDates() -> [Date] {
        guard let intervals = userDefaults.array(forKey: UserDefaultsKeys.promptDates) as? [Double] else {
            return []
        }
        return intervals.map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    /// Opens the App Store write-a-review page for the configured app ID.
    public func openAppStore() throws {
        guard let url = URL(string: "https://apps.apple.com/app/id\(configuration.appID)?action=write-review") else {
            throw AppStoreReviewPromptError.reviewURLNotValid
        }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
