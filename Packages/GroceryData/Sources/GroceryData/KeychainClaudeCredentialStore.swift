import Foundation
import GroceryDomain
import Security

/// Stores the developer's Claude API key as a device-only Keychain item.
///
/// UI-facing code uses only `hasCredential`; the provider reads the secret for
/// immediate authentication and never places it in Model Run or Model Trace data.
public struct KeychainClaudeCredentialStore: ClaudeCredentialStore, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.example.GroceryApp",
        account: String = "claude-api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func hasCredential() async -> Bool {
        readData() != nil
    }

    public func credential() async -> String? {
        guard let data = readData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(apiKey: String) async throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw ClaudeCredentialStoreError.invalidCredential
        }

        let query = baseQuery()
        let data = Data(normalizedKey.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [
            kSecValueData: data
        ] as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ClaudeCredentialStoreError.keychainFailure(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw ClaudeCredentialStoreError.keychainFailure(status: updateStatus)
        }
    }

    public func remove() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClaudeCredentialStoreError.keychainFailure(status: status)
        }
    }

    private func readData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
