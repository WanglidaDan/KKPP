import AuthenticationServices
import Foundation

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var userId: String = ""
    @Published private(set) var displayName: String = "KKPP User"
    @Published private(set) var isSignedIn = false

    private let userIdKey = "kkpp.apple.userId"
    private let displayNameKey = "kkpp.apple.displayName"

    override init() {
        super.init()
        loadStoredIdentity()
    }

    func loadStoredIdentity() {
        let defaults = UserDefaults.standard
        if let storedId = defaults.string(forKey: userIdKey), !storedId.isEmpty {
            userId = storedId
            displayName = defaults.string(forKey: displayNameKey) ?? "KKPP User"
            isSignedIn = true
        }
    }

    func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        let formatter = PersonNameComponentsFormatter()
        let fullName = formatter.string(from: credential.fullName ?? PersonNameComponents())
        let resolvedName = fullName.isEmpty ? "KKPP User" : fullName

        userId = credential.user
        displayName = resolvedName
        isSignedIn = true

        let defaults = UserDefaults.standard
        defaults.set(userId, forKey: userIdKey)
        defaults.set(displayName, forKey: displayNameKey)
    }
}
