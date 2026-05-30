# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
swift build

# Run all tests (macOS)
swift test

# Run a single test
swift test --filter "CheckReviewRequestTests/callsReviewRequesterAtThreshold"

# Run tests on iOS Simulator
xcodebuild test \
  -scheme AppStoreReviewPrompt \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

## Architecture

Single-file Swift package library (`Sources/AppStoreReviewPrompt/AppStoreReviewPrompt.swift`) targeting iOS 16+ and macOS 14+. No external dependencies.

**Core class:** `AppStoreReviewPrompt` (`@MainActor final class`) — all state lives in `UserDefaults`. Three keys: completion count, last-prompted version, prompt date history.

**Gate logic in `checkReviewRequest()`** (all must pass to fire the prompt):
1. Completion count ≥ `configuration.promoteOnTime`
2. Current bundle version ≠ last-prompted version
3. `canPrompt()` — ≤3 prompts in rolling 365-day window AND ≥60 days since last prompt

**Testability seams** — two injectable protocols keep tests hermetic:
- `DateProviding` / `SystemDateProvider` — injectable clock; tests use `StubDateProvider` (mutable `var now`)
- `BundleProviding` — injectable version string; tests use `StubBundle`
- `reviewRequester` closure — injectable in `init` to capture call count

**Platform split:** `defaultReviewRequester()` uses `#if os(iOS)` / `#elseif os(macOS)` to call `AppStore.requestReview(in:)` with the appropriate scene/view-controller. SwiftUI callers should inject `@Environment(\.requestReview)` instead.

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest. Each test gets its own isolated `UserDefaults` suite via `UUID().uuidString` as suite name.
