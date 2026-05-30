import Testing
import Foundation
@testable import AppStoreReviewPrompt

// MARK: - StubDateProvider

private final class StubDateProvider: DateProviding, @unchecked Sendable {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }
}

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
        let clockV1 = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 0))
        let promptV1 = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "1.0"),
            dateProvider: clockV1
        )
        try promptV1.checkReviewRequest() // records "1.0"

        // App updated to 2.0, 61 days later (past the minimum gap).
        defaults.removeObject(forKey: "processCompletedCountKey")
        let clockV2 = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 61 * 24 * 3600))
        let promptV2 = AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: "2.0"),
            dateProvider: clockV2
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

// MARK: - Rate-limit tests

@Suite("Rate limiting")
@MainActor
struct RateLimitTests {

    private func makePrompt(
        defaults: UserDefaults,
        version: String = "1.0",
        dateProvider: StubDateProvider,
        onRequest: @escaping @MainActor () -> Void = {}
    ) -> AppStoreReviewPrompt {
        AppStoreReviewPrompt(
            configuration: ReviewPromoConfiguration(appID: "app", promoteOnTime: 1),
            userDefaults: defaults,
            bundle: StubBundle(version: version),
            dateProvider: dateProvider,
            reviewRequester: onRequest
        )
    }

    @Test("Blocks prompt when fewer than 60 days have passed since last prompt")
    func blocksWhenTooSoon() throws {
        let defaults = makeUserDefaults()
        let clock = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 0))
        var count = 0

        // First prompt fires.
        try makePrompt(defaults: defaults, version: "1.0", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 1)

        // 30 days later, new version — should be blocked by minimum gap.
        clock.now = Date(timeIntervalSinceReferenceDate: 30 * 24 * 3600)
        defaults.removeObject(forKey: "processCompletedCountKey")
        try makePrompt(defaults: defaults, version: "2.0", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 1) // no additional prompt
    }

    @Test("Allows prompt when 60 or more days have passed since last prompt")
    func allowsAfterMinimumGap() throws {
        let defaults = makeUserDefaults()
        let clock = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 0))
        var count = 0

        try makePrompt(defaults: defaults, version: "1.0", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 1)

        // 61 days later, new version — should be allowed.
        clock.now = Date(timeIntervalSinceReferenceDate: 61 * 24 * 3600)
        defaults.removeObject(forKey: "processCompletedCountKey")
        try makePrompt(defaults: defaults, version: "2.0", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 2)
    }

    @Test("Blocks 4th prompt within 365 days even when spacing is sufficient")
    func blocksAfterThreePromptsInYear() throws {
        let defaults = makeUserDefaults()
        let clock = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 0))
        var count = 0

        // 3 prompts spaced 61 days apart — all should fire.
        for i in 0..<3 {
            clock.now = Date(timeIntervalSinceReferenceDate: Double(i) * 61 * 24 * 3600)
            defaults.removeObject(forKey: "processCompletedCountKey")
            try makePrompt(defaults: defaults, version: "v\(i)", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        }
        #expect(count == 3)

        // 4th prompt still within 365-day window — should be blocked.
        clock.now = Date(timeIntervalSinceReferenceDate: 3 * 61 * 24 * 3600)
        defaults.removeObject(forKey: "processCompletedCountKey")
        try makePrompt(defaults: defaults, version: "v3", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 3) // still 3, not 4
    }

    @Test("Allows prompt again once oldest entry falls outside the 365-day window")
    func allowsAfterWindowExpires() throws {
        let defaults = makeUserDefaults()
        let clock = StubDateProvider(now: Date(timeIntervalSinceReferenceDate: 0))
        var count = 0

        // Fill up 3 prompts.
        for i in 0..<3 {
            clock.now = Date(timeIntervalSinceReferenceDate: Double(i) * 61 * 24 * 3600)
            defaults.removeObject(forKey: "processCompletedCountKey")
            try makePrompt(defaults: defaults, version: "v\(i)", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        }
        #expect(count == 3)

        // Advance past 365 days from the first prompt — the window slides and opens a slot.
        clock.now = Date(timeIntervalSinceReferenceDate: 370 * 24 * 3600)
        defaults.removeObject(forKey: "processCompletedCountKey")
        try makePrompt(defaults: defaults, version: "v_new", dateProvider: clock, onRequest: { count += 1 }).checkReviewRequest()
        #expect(count == 4)
    }
}
