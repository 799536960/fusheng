import Foundation
import Security

protocol SecItemClient {
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemSecItemClient: SecItemClient {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, result)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainService: APIKeyProviding {
    private let service = "com.fusheng.voiceinput"
    private let account = "dashscope-api-key"
    private let client: SecItemClient

    init(client: SecItemClient = SystemSecItemClient()) {
        self.client = client
    }

    func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = client.update(query, attributes: updateAttributes)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppError.recorderFailed("Keychain 保存失败：\(updateStatus)")
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = client.add(attributes)
        guard status == errSecSuccess else {
            throw AppError.recorderFailed("Keychain 保存失败：\(status)")
        }
    }

    func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = client.copyMatching(query, result: &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.recorderFailed("Keychain 读取失败：\(status)")
        }
        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw AppError.recorderFailed("Keychain 读取失败：无效 UTF-8 数据")
        }
        return apiKey
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = client.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.recorderFailed("Keychain 删除失败：\(status)")
        }
    }
}
