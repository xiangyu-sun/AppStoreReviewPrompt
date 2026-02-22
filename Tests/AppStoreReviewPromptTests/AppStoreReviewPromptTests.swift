import Testing
import Foundation
@testable import AppStoreReviewPrompt

// MARK: - Helpers

/// Returns a fresh, isolated UserDefaults suite for each test.
private func makeUserDefaults() -> UserDefaults {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    return defaults
}

/// A lightweight stub that satisfies `BundleProviding` without subclassing `Bundle`.
private struct StubBundle: BundleProviding {
    var bundleVersion: String?

    init(version: String? = "1.0") {
        bundleVersion = version
    }
}

// MARK: - ReviewPromoConfiguration

@Suite("ReviewPromoConfiguration")
struct ReviewPromoConfigurationTests {

    @Test("Stores appID and promoteOnTime")
    func storesValues() {
        let config = ReviewPromoConfiguration(appID: "123456789", promoteOnTime: 3)
        #expect(config.appID == "123456789")
        #expect(config.promoteOnTime == 3)
    }
}

// MARK: - AppStoreReviewPromptError

@Suite("AppStoreReviewPromptError")
struct AppStoreReviewPromptErrorTests {

    @Test("currentVersionNotFound debug description")
    func currentVersionNotFoundDescription() {
        #expect(
            AppStoreReviewPromptError.currentVersionNotFound.debugDescription ==
            "Expected to find a bundle version in the info dictionary"
        )
    }

    @Test("reviewURLNotValid debug description")
    func reviewURLNotValidDescription() {
        #expect(
            AppStoreReviewPromptError.reviewURLNotValid.debugDescription ==
            "Expected a valid review URL"
        )
    }

    @Test("Both cases conform to Error")
    func conformsToError() {
        let errors: [any Error] = [
            AppStoreReviewPromptError.currentVersionNotFound,
            AppStoreReviewPromptError.reviewURLNotValid
        ]
        #expect(errors.count == 2)
    }
}

// MARK: - checkReviewRequest

@Suite("checkReviewRequest")
@MainActor
struct CheckReviewRequestTests {

    @Test("Increments counter on each call")
    func incrementsCounter() throws {
        let defaults = makeUserDefaults()
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 100),
            userDefaults: defaults,
            bundle: StubBundle()
        )

        try prompt.checkReviewRequest()
        #expect(defaults.integer(forKey: "processCompletedCountKey") == 1)

        try prompt.checkReviewRequest()
        #expect(defaults.integer(forKey: "processCompletedCountKey") == 2)
    }

    @Test("Does not record version before threshold is reached")
    func doesNotRecordVersionBeforeThreshold() throws {
        let defaults = makeUserDefaults()
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 5),
            userDefaults: defaults,
            bundle: StubBundle()
        )

        try prompt.checkReviewRequest() // count = 1, threshold = 5
        #expect(defaults.string(forKey: "lastVersionPromptedForReviewKey") == nil)
    }

    @Test("Records version when threshold is reached")
    func recordsVersionAtThreshold() throws {
        let defaults = makeUserDefaults()
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "2.0")
        )

        try prompt.checkReviewRequest() // count = 1 == threshold
        #expect(defaults.string(forKey: "lastVersionPromptedForReviewKey") == "2.0")
    }

    @Test("Does not re-prompt for the same version")
    func doesNotRepromptSameVersion() throws {
        let defaults = makeUserDefaults()
        // First prompt records "1.0"
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0")
        )
        try prompt.checkReviewRequest()
        #expect(defaults.string(forKey: "lastVersionPromptedForReviewKey") == "1.0")

        // New session with same version — should not re-prompt
        defaults.removeObject(forKey: "processCompletedCountKey")
        let promptSameVersion = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0")
        )
        try promptSameVersion.checkReviewRequest()
        #expect(defaults.string(forKey: "lastVersionPromptedForReviewKey") == "1.0")
    }

    @Test("Prompts again for a new app version")
    func promptsAgainForNewVersion() throws {
        let defaults = makeUserDefaults()
        let promptV1 = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0")
        )
        try promptV1.checkReviewRequest() // records "1.0"

        // App updated to 2.0
        defaults.removeObject(forKey: "processCompletedCountKey")
        let promptV2 = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "2.0")
        )
        try promptV2.checkReviewRequest()
        #expect(defaults.string(forKey: "lastVersionPromptedForReviewKey") == "2.0")
    }

    @Test("Throws currentVersionNotFound when bundle has no version")
    func throwsWhenVersionMissing() {
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: makeUserDefaults(),
            bundle: StubBundle(version: nil)
        )

        #expect(throws: AppStoreReviewPromptError.currentVersionNotFound) {
            try prompt.checkReviewRequest()
        }
    }

    @Test("Calls reviewRequester when threshold is met")
    func callsReviewRequesterAtThreshold() throws {
        var reviewRequestCount = 0
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: makeUserDefaults(),
            bundle: StubBundle(version: "1.0"),
            reviewRequester: { reviewRequestCount += 1 }
        )

        try prompt.checkReviewRequest()
        #expect(reviewRequestCount == 1)
    }

    @Test("Does not call reviewRequester below threshold")
    func doesNotCallReviewRequesterBelowThreshold() throws {
        var reviewRequestCount = 0
        let prompt = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 3),
            userDefaults: makeUserDefaults(),
            bundle: StubBundle(version: "1.0"),
            reviewRequester: { reviewRequestCount += 1 }
        )

        try prompt.checkReviewRequest() // count = 1
        try prompt.checkReviewRequest() // count = 2
        #expect(reviewRequestCount == 0)
    }

    @Test("Does not call reviewRequester again for the same version")
    func doesNotCallReviewRequesterForSameVersion() throws {
        var reviewRequestCount = 0
        let defaults = makeUserDefaults()

        let promptV1 = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0"),
            reviewRequester: { reviewRequestCount += 1 }
        )
        try promptV1.checkReviewRequest() // triggers, count becomes 1
        #expect(reviewRequestCount == 1)

        // Same version, new session
        defaults.removeObject(forKey: "processCompletedCountKey")
        let promptV1Again = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0"),
            reviewRequester: { reviewRequestCount += 1 }
        )
        try promptV1Again.checkReviewRequest() // should not trigger
        #expect(reviewRequestCount == 1)
    }
}
