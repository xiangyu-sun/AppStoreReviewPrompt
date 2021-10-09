import StoreKit

public struct ReviewPromoConfiguration {
    public init(appID: String, promoteOnTime: Int) {
        self.appID = appID
        self.promoteOnTime = promoteOnTime
    }
    
    public let appID: String
    public let promoteOnTime: Int
}

struct UserDefaultsKeys {
    static let processCompletedCountKey = "processCompletedCountKey"
    static let lastVersionPromptedForReviewKey = "lastVersionPromptedForReviewKey"
}

public final class AppStoreReviewPrompt {

    let configuration: ReviewPromoConfiguration
    
    public init(configuration: ReviewPromoConfiguration) {
        self.configuration = configuration
    }
    
    public func checkReviewRequest() {
          // If the count has not yet been stored, this will return 0
          var count = UserDefaults.standard.integer(forKey: UserDefaultsKeys.processCompletedCountKey)
          count += 1
          UserDefaults.standard.set(count, forKey: UserDefaultsKeys.processCompletedCountKey)
          
          // Get the current bundle version for the app
          let infoDictionaryKey = kCFBundleVersionKey as String
          guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
              else { fatalError("Expected to find a bundle version in the info dictionary") }
          
          let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastVersionPromptedForReviewKey)
          
        if count >= configuration.promoteOnTime && currentVersion != lastVersionPromptedForReview {
              let twoSecondsFromNow = DispatchTime.now() + 2.0
              DispatchQueue.main.asyncAfter(deadline: twoSecondsFromNow){
                  SKStoreReviewController.requestReview()
                  UserDefaults.standard.set(currentVersion, forKey: UserDefaultsKeys.lastVersionPromptedForReviewKey)
              }
          }
      }
    
    public func openAppStore() {
        guard let writeReviewURL = URL(string: "https://itunes.apple.com/app/\(configuration.appID)?action=write-review")
            else { fatalError("Expected a valid URL") }
        UIApplication.shared.open(writeReviewURL, options: [:], completionHandler: nil)
    }
}
