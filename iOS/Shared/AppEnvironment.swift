import Foundation
import Security
import CryptoKit

enum AppEnvironment {
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.com.example.relay"
    }

    static var keychainAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var defaultBackendURL: String {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "DefaultBackendURL") as? String,
              !configured.isEmpty, !configured.contains("$(") else { return "" }
        return configured
    }

    static var backendURL: String {
        get {
            if let saved = defaults.string(forKey: "backendURL"), !saved.isEmpty { return saved }
            return defaultBackendURL
        }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "backendURL") }
    }

    static var settingsPreview: String {
        get { defaults.string(forKey: "settingsPreview") ?? "Import a job to prepare your referral outreach." }
        set { defaults.set(newValue, forKey: "settingsPreview") }
    }

    static func reset() {
        defaults.removeObject(forKey: "backendURL")
        defaults.removeObject(forKey: "settingsPreview")
    }

    static func sharedDirectory(named name: String) throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw SharedStorageError.appGroupUnavailable
        }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum SharedStorageError: LocalizedError {
    case appGroupUnavailable
    case keychain(OSStatus)
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared storage is unavailable. Enable the same App Group for Relay and its share extension in Xcode."
        case .keychain:
            return "Relay could not save the connection securely. Check the app's Keychain Sharing entitlement."
        case .invalidIdentifier:
            return "The saved share has an invalid identifier."
        }
    }
}

enum SharedCredentials {
    private static var query: [String: Any] {
        var value: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "relay.service-session",
            kSecAttrAccount as String: "device"
        ]
        if let group = AppEnvironment.keychainAccessGroup { value[kSecAttrAccessGroup as String] = group }
        return value
    }

    static var token: String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String?) throws {
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SharedStorageError.keychain(status) }
            return
        }
        let value = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SharedStorageError.keychain(update) }
        var request = query
        request[kSecValueData as String] = value
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw SharedStorageError.keychain(status) }
    }

    static var fingerprint: String? {
        token.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }
}

struct PendingShare: Codable, Identifiable, Sendable {
    let id: String
    let url: String
    let sharedText: String?
    let title: String?
    let company: String?
    let domain: String?
    let createdAt: String
    let destination: String?
    let credentialFingerprint: String?

    var belongsToCurrentConnection: Bool {
        (destination == nil || destination == AppEnvironment.backendURL) &&
        (credentialFingerprint == nil || credentialFingerprint == SharedCredentials.fingerprint)
    }
}

enum SharedInbox {
    // One atomic file per import avoids read/modify/write races between app and extension.
    static func enqueue(
        url: String,
        sharedText: String? = nil,
        title: String? = nil,
        company: String? = nil,
        domain: String? = nil
    ) throws -> PendingShare {
        let pending = PendingShare(
            id: UUID().uuidString,
            url: url,
            sharedText: sharedText,
            title: title,
            company: company,
            domain: domain,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            destination: AppEnvironment.backendURL.isEmpty ? nil : AppEnvironment.backendURL,
            credentialFingerprint: SharedCredentials.fingerprint
        )
        let file = try location(id: pending.id)
        try JSONEncoder().encode(pending).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return pending
    }

    static func load() -> [PendingShare] {
        guard let directory = try? AppEnvironment.sharedDirectory(named: "PendingShares"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(PendingShare.self, from: data)
        }.filter(\.belongsToCurrentConnection).sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(id: String) throws {
        let file = try location(id: id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    static func clear() throws {
        let directory = try AppEnvironment.sharedDirectory(named: "PendingShares")
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func location(id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw SharedStorageError.invalidIdentifier }
        return try AppEnvironment.sharedDirectory(named: "PendingShares").appendingPathComponent(id).appendingPathExtension("json")
    }
}
