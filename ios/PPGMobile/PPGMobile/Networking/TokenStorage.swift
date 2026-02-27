import Foundation
import Security

// MARK: - Error Types

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Token not found in keychain"
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)"
        case .invalidData:
            return "Token data could not be encoded or decoded"
        }
    }
}

// MARK: - Protocol

protocol TokenStoring {
    func save(token: String, for connectionId: UUID) throws
    func load(for connectionId: UUID) throws -> String
    func delete(for connectionId: UUID) throws
}

// MARK: - Implementation

struct TokenStorage: TokenStoring {
    private let serviceName = "com.ppg.mobile"

    func save(token: String, for connectionId: UUID) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        var query = baseQuery(for: connectionId)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            let updateStatus = SecItemUpdate(
                baseQuery(for: connectionId) as CFDictionary,
                updateAttributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(for connectionId: UUID) throws -> String {
        var query = baseQuery(for: connectionId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return token
    }

    func delete(for connectionId: UUID) throws {
        let status = SecItemDelete(baseQuery(for: connectionId) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private

    private func baseQuery(for connectionId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString
        ]
    }
}
