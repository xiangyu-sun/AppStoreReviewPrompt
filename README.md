# AppStoreReviewPrompt

A lightweight Swift package that triggers App Store review prompts at the right moment — not too early, not too often.

## Features

- Prompt after a configurable number of completed user actions
- Per-version gating — only prompts once per app version
- Built-in rate limiting mirroring Apple's OS cap: max 3 prompts per rolling 365-day window, minimum 60 days between prompts
- Fully testable via injectable clock, bundle, and review requester
- iOS 16+ and macOS 14+

## Installation

### Swift Package Manager

Add the package in Xcode via **File → Add Package Dependencies**, or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/xiangyu-sun/AppStoreReviewPrompt.git", from: "1.0.0")
]
```

## Usage

### 1. Configure

```swift
import AppStoreReviewPrompt

let prompt = AppStoreReviewPrompt(
    configuration: ReviewPromoConfiguration(
        appID: "123456789",   // Your App Store app ID
        promoteOnTime: 5      // Prompt after 5 completed actions
    )
)
```

### 2. Call on meaningful user actions

```swift
// After a user completes an action (export, save, purchase, etc.)
try? prompt.checkReviewRequest()
```

The prompt fires when **all** of the following are true:

| Condition | Detail |
|-----------|--------|
| Action threshold reached | `promoteOnTime` completions accumulated |
| New version | Current bundle version not yet prompted |
| Yearly cap not hit | Fewer than 3 prompts in the past 365 days |
| Minimum gap elapsed | At least 60 days since the last prompt |

### 3. Link to the App Store review page (optional)

```swift
try? prompt.openAppStore()
// Opens: https://apps.apple.com/app/id<appID>?action=write-review
```

### SwiftUI

Inject `@Environment(\.requestReview)` for SwiftUI apps:

```swift
import SwiftUI
import StoreKit
import AppStoreReviewPrompt

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Button("Complete Action") {
            let prompt = AppStoreReviewPrompt(
                configuration: ReviewPromoConfiguration(appID: "123456789", promoteOnTime: 5),
                reviewRequester: { requestReview() }
            )
            try? prompt.checkReviewRequest()
        }
    }
}
```

## iOS 17+ Privacy Note

iOS 17 requires a `NSUserDefaultsUsagDescription` key in `Info.plist` if your app uses `UserDefaults` for storing prompt history. Add it if your app targets iOS 17+:

```xml
<key>NSUserDefaultsUsagDescription</key>
<string>Tracks when to show the App Store review prompt.</string>
```

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS      | 16.0    |
| macOS    | 14.0    |

Swift Tools Version: 6.0

## License

MIT
