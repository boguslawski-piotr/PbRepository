/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

open class PbUserDefaultsRepository: PbSimpleRepository, PbSimpleRepositoryAsync {
    public let name: String
    public let coder: PbCoder
    public let userDefaults: UserDefaults

    public init(name: String = "", coder: PbCoder = PropertyListCoder(), userDefaults: UserDefaults = UserDefaults.standard) {
        self.name = name
        self.coder = coder
        self.userDefaults = userDefaults
    }

    open func delete(_ name: String) throws {
        userDefaults.removeObject(forKey: name)
    }

    open func deleteAsync(_ name: String) async throws {
        try delete(name)
    }

    open func store<T: Encodable>(item: T, to name: String) throws {
        let data = try coder.encode(item)
        userDefaults.set(data, forKey: name)
    }

    open func storeAsync<T: Encodable>(item: T, to name: String) async throws {
        try store(item: item, to: name)
    }

    open func retrieve<T: Decodable>(itemOf type: T.Type, from name: String) throws -> T? {
        if let data = userDefaults.data(forKey: name) {
            return try coder.decode(T.self, from: data)
        }
        return nil
    }

    open func retrieveAsync<T: Decodable>(itemOf type: T.Type, from name: String) async throws -> T? {
        return try retrieve(itemOf: type, from: name)
    }
}
