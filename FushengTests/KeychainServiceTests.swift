import Foundation
import Security
import XCTest
@testable import Fusheng

final class KeychainServiceTests: XCTestCase {
    func testLoadAPIKeyReturnsNilWhenItemIsMissing() throws {
        let client = FakeSecItemClient()
        let service = KeychainService(client: client)

        XCTAssertNil(try service.loadAPIKey())
    }

    func testSaveThenLoadRoundTripUsingFakeClient() throws {
        let client = FakeSecItemClient()
        let service = KeychainService(client: client)

        try service.saveAPIKey("dashscope-key")

        XCTAssertEqual(try service.loadAPIKey(), "dashscope-key")
    }

    func testSaveExistingItemUsesUpdatePathAndPreservesOldKeyWhenUpdateFails() throws {
        let client = FakeSecItemClient(storedData: Data("old-key".utf8))
        client.updateStatus = errSecAuthFailed
        let service = KeychainService(client: client)

        XCTAssertThrowsError(try service.saveAPIKey("new-key"))
        XCTAssertEqual(client.storedData, Data("old-key".utf8))
        XCTAssertEqual(client.updateCallCount, 1)
        XCTAssertEqual(client.addCallCount, 0)
        XCTAssertEqual(client.deleteCallCount, 0)
    }

    func testSaveMissingItemUsesAddPath() throws {
        let client = FakeSecItemClient()
        let service = KeychainService(client: client)

        try service.saveAPIKey("new-key")

        XCTAssertEqual(client.updateCallCount, 1)
        XCTAssertEqual(client.addCallCount, 1)
        XCTAssertEqual(client.deleteCallCount, 0)
        XCTAssertEqual(client.storedData, Data("new-key".utf8))
    }

    func testDeleteSucceedsAndMissingDeleteDoesNotThrow() throws {
        let client = FakeSecItemClient(storedData: Data("old-key".utf8))
        let service = KeychainService(client: client)

        XCTAssertNoThrow(try service.deleteAPIKey())
        XCTAssertNil(client.storedData)
        XCTAssertNoThrow(try service.deleteAPIKey())
    }

    func testSuccessfulReadWithInvalidUTF8DataThrows() {
        let client = FakeSecItemClient(storedData: Data([0xff]))
        let service = KeychainService(client: client)

        XCTAssertThrowsError(try service.loadAPIKey())
    }
}

private final class FakeSecItemClient: SecItemClient {
    var storedData: Data?
    var updateStatus: OSStatus?
    var addStatus: OSStatus?
    var deleteStatus: OSStatus?
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(storedData: Data? = nil) {
        self.storedData = storedData
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addCallCount += 1
        if let addStatus {
            return addStatus
        }
        guard storedData == nil else {
            return errSecDuplicateItem
        }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCallCount += 1
        if let updateStatus {
            return updateStatus
        }
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        guard let storedData else {
            return errSecItemNotFound
        }
        result?.pointee = storedData as AnyObject
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        if let deleteStatus {
            return deleteStatus
        }
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = nil
        return errSecSuccess
    }
}
