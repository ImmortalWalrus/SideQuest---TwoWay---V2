import Foundation

@Observable
final class FirebaseService {
    static let shared = FirebaseService()

    private(set) var currentUserId: String?
    private(set) var isAuthenticated: Bool = false
    private(set) var userEmail: String?
    private(set) var authError: String?

    private init() {}

    func checkExistingSession() {
        if let savedId = UserDefaults.standard.string(forKey: "offlineUserId") {
            currentUserId = savedId
            userEmail = UserDefaults.standard.string(forKey: "offlineUserEmail")
            isAuthenticated = true
        }
    }

    func signUpWithEmail(_ email: String, password: String) async throws {
        authError = nil
        guard password.count >= 6 else {
            let msg = "Password must be at least 6 characters."
            authError = msg
            throw FirebaseServiceError.authFailed(msg)
        }
        let uid = UUID().uuidString
        currentUserId = uid
        userEmail = email
        isAuthenticated = true
        UserDefaults.standard.set(uid, forKey: "offlineUserId")
        UserDefaults.standard.set(email, forKey: "offlineUserEmail")
    }

    func signInWithEmail(_ email: String, password: String) async throws {
        authError = nil
        let uid = UserDefaults.standard.string(forKey: "offlineUserId") ?? UUID().uuidString
        currentUserId = uid
        userEmail = email
        isAuthenticated = true
        UserDefaults.standard.set(uid, forKey: "offlineUserId")
        UserDefaults.standard.set(email, forKey: "offlineUserEmail")
    }

    func sendPasswordReset(email: String) async throws {
        authError = nil
    }

    func signInWithGoogle() async throws {
        authError = nil
        let uid = UserDefaults.standard.string(forKey: "offlineUserId") ?? UUID().uuidString
        currentUserId = uid
        userEmail = "user@offline.local"
        isAuthenticated = true
        UserDefaults.standard.set(uid, forKey: "offlineUserId")
        UserDefaults.standard.set("user@offline.local", forKey: "offlineUserEmail")
    }

    func signOut() {
        currentUserId = nil
        userEmail = nil
        isAuthenticated = false
        authError = nil
    }
}

nonisolated enum FirebaseServiceError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case userNotFound
    case uploadFailed
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "You must be signed in."
        case .userNotFound: "No user found with that username."
        case .uploadFailed: "Failed to upload data."
        case .authFailed(let message): message
        }
    }
}
