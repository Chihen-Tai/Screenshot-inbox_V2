import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let service = "ScreenshotInbox.GoogleAIStudio"
    private let account = "apiKey"

    private init() {}

    func saveGoogleAIStudioAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    func readGoogleAIStudioAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.readFailed(status) }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return key
    }

    func deleteGoogleAIStudioAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    enum KeychainError: LocalizedError {
        case encodingFailed
        case decodingFailed
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode API key."
            case .decodingFailed: return "Failed to decode stored key."
            case .saveFailed(let s): return "Keychain save failed (\(s))."
            case .readFailed(let s): return "Keychain read failed (\(s))."
            case .deleteFailed(let s): return "Keychain delete failed (\(s))."
            }
        }
    }
}
