//
//  SavedTokenStore.swift
//  Albert Script Runner
//

import Foundation
import LocalAuthentication
import Security

enum SavedTokenStoreError: LocalizedError {
    case invalidToken
    case tokenNotFound
    case keychainError(OSStatus)
    case indexReadFailed
    case indexWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid token."
        case .tokenNotFound:
            return "Token not found."
        case .keychainError(let status):
            if status == errSecMissingEntitlement {
                return "Keychain access not permitted. Ensure Keychain Sharing is enabled and the app is signed."
            }
            return "Keychain error: \(status)."
        case .indexReadFailed:
            return "Failed to read saved tokens."
        case .indexWriteFailed:
            return "Failed to save tokens."
        }
    }
}

final class SavedTokenStore {
    static let shared = SavedTokenStore()

    private let service: String
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(service: String? = nil, indexURL: URL? = nil) {
        let bundleId = Bundle.main.bundleIdentifier ?? "AlbertScriptRunner"
        self.service = service ?? "\(bundleId).saved-jwt"
        self.indexURL = indexURL ?? SavedTokenStore.defaultIndexURL(bundleId: bundleId)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func listMetadata() throws -> [SavedTokenMetadata] {
        do {
            return try loadIndex()
        } catch {
            throw SavedTokenStoreError.indexReadFailed
        }
    }

    func saveToken(jwt: String, baseURL: String, label: String? = nil) throws -> SavedTokenMetadata {
        let trimmedToken = jwt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = decodeJwtSummary(trimmedToken) else {
            throw SavedTokenStoreError.invalidToken
        }

        let tenantId = summary.tenantId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTenantId = (tenantId?.isEmpty == false) ? tenantId! : "Unknown Tenant"

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelBaseURL = trimmedBaseURL.hasSuffix("/")
            ? String(trimmedBaseURL.dropLast())
            : trimmedBaseURL

        let autoLabel = "\(safeTenantId) | \(labelBaseURL)"
        let finalLabel = (label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? label!.trimmingCharacters(in: .whitespacesAndNewlines)
            : autoLabel

        let metadata = SavedTokenMetadata(
            id: UUID(),
            label: finalLabel,
            tenantId: safeTenantId,
            baseURL: trimmedBaseURL,
            expiresAt: summary.expiresAt,
            createdAt: Date()
        )

        let data = Data(trimmedToken.utf8)
        try saveKeychainToken(id: metadata.id, data: data)

        var items = (try? loadIndex()) ?? []
        items.append(metadata)
        do {
            try saveIndex(items)
        } catch {
            _ = deleteKeychainToken(id: metadata.id)
            throw SavedTokenStoreError.indexWriteFailed
        }

        return metadata
    }

    func loadToken(id: UUID, prompt: String = "Unlock saved tokens", context: LAContext? = nil) throws -> String {
        let data = try loadKeychainToken(id: id, prompt: prompt, context: context)
        guard let token = String(data: data, encoding: .utf8) else {
            throw SavedTokenStoreError.keychainError(errSecInternalError)
        }
        return token
    }

    func renameToken(id: UUID, newLabel: String) throws -> SavedTokenMetadata {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SavedTokenStoreError.indexWriteFailed }

        var items = try loadIndex()
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            throw SavedTokenStoreError.tokenNotFound
        }

        items[idx].label = trimmed
        do {
            try saveIndex(items)
        } catch {
            throw SavedTokenStoreError.indexWriteFailed
        }

        return items[idx]
    }

    func deleteToken(id: UUID) throws {
        _ = deleteKeychainToken(id: id)

        var items = try loadIndex()
        items.removeAll { $0.id == id }
        do {
            try saveIndex(items)
        } catch {
            throw SavedTokenStoreError.indexWriteFailed
        }
    }

    // MARK: - Index Storage

    private func loadIndex() throws -> [SavedTokenMetadata] {
        if !FileManager.default.fileExists(atPath: indexURL.path) {
            return []
        }
        let data = try Data(contentsOf: indexURL)
        return try decoder.decode([SavedTokenMetadata].self, from: data)
    }

    private func saveIndex(_ items: [SavedTokenMetadata]) throws {
        let data = try encoder.encode(items)
        try ensureIndexDirectory()
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureIndexDirectory() throws {
        let dir = indexURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private static func defaultIndexURL(bundleId: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent(bundleId, isDirectory: true)
        return (dir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("SavedTokensIndex.json")
    }

    // MARK: - Keychain

    private func saveKeychainToken(id: UUID, data: Data) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            nil
        ) else {
            throw SavedTokenStoreError.keychainError(errSecInternalError)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            _ = deleteKeychainToken(id: id)
            let retry = SecItemAdd(query as CFDictionary, nil)
            if retry != errSecSuccess {
                throw SavedTokenStoreError.keychainError(retry)
            }
            return
        }

        if status != errSecSuccess {
            throw SavedTokenStoreError.keychainError(status)
        }
    }

    private func loadKeychainToken(id: UUID, prompt: String, context: LAContext?) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: prompt
        ]

        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw SavedTokenStoreError.tokenNotFound
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw SavedTokenStoreError.keychainError(status)
        }

        return data
    }

    @discardableResult
    private func deleteKeychainToken(id: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
