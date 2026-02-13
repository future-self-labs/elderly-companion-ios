import Foundation

@Observable
final class AuthService {
    private(set) var isVerifying: Bool = false
    private(set) var verificationSent: Bool = false
    private(set) var error: String?

    private let api = APIClient.shared

    /// Send OTP code to the given phone number
    func sendOTP(to phoneNumber: String) async throws {
        isVerifying = true
        error = nil

        do {
            _ = try await api.sendOTP(phoneNumber: phoneNumber)
            verificationSent = true
        } catch {
            self.error = error.localizedDescription
            throw error
        }

        isVerifying = false
    }

    /// Validate the OTP code and return the user ID
    @discardableResult
    func validateOTP(phoneNumber: String, code: String) async throws -> String {
        isVerifying = true
        error = nil

        do {
            let response = try await api.validateOTP(phoneNumber: phoneNumber, code: code)
            UserDefaults.standard.set(response.userId, forKey: "userId")
            isVerifying = false
            return response.userId
        } catch {
            self.error = error.localizedDescription
            isVerifying = false
            throw error
        }
    }

    /// Get the stored user ID
    var currentUserId: String? {
        UserDefaults.standard.string(forKey: "userId")
    }

    func reset() {
        isVerifying = false
        verificationSent = false
        error = nil
    }
}
