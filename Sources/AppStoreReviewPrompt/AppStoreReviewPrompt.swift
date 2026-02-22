import StoreKit
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

    public let configuration: ReviewPromoConfiguration
    private let userDefaults: UserDefaults
    private let bundleProvider: any BundleProviding
    private let reviewRequester: @MainActor () -> Void

    public init(
        configuration: ReviewPromoConfiguration,
        userDefaults: UserDefaults = .standard,
        bundle: any BundleProviding = Bundle.main,
        reviewRequester: (@MainActor () -> Void)? = nil
    ) {
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.bundleProvider = bundle
        self.reviewRequester = reviewRequester ?? { defaultReviewRequester() }
    }

    /// Increments the process-completion counter and requests a review when the
    /// threshold is met and the current app version hasn't been prompted yet.
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

        userDefaults.set(currentVersion, forKey: UserDefaultsKeys.lastVersionPromptedForReview)
        reviewRequester()
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
