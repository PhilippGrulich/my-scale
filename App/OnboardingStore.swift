import Foundation

/// First-launch flag. Mirrors `ProfileStore`'s lightweight UserDefaults pattern.
/// `isCompleted` is false on a fresh install (the welcome flow runs), true once
/// the user finishes onboarding.
enum OnboardingStore {
    private static let key = "myopenscale.onboarding.completed.v1"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)   // false on miss = needs onboarding
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Clear the flag so onboarding runs again (developer / testing).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
