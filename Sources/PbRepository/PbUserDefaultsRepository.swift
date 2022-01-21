/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

final public class PbUserDefaultsRepository : PbSimpleRepository, PbSimpleRepositoryAsync
{
    public let name : String
    private let coder : PbCoder
    private let userDefaults : UserDefaults

    public init(name : String, coder : PbCoder? = nil, userDefaults : UserDefaults? = nil) {
        self.name = name
        self.coder = coder ?? PropertyListCoder()
        self.userDefaults = userDefaults ?? UserDefaults.standard
    }
    
    public func delete(_ name : String) throws {
        userDefaults.removeObject(forKey: name)
    }
    
    public func deleteAsync(_ name : String) async throws {
        try delete(name)
    }

    public func store<T: Encodable>(item : T, to name : String) throws {
        let data = try coder.encode(item)
        userDefaults.set(data, forKey: name)
    }

    public func storeAsync<T: Encodable>(item : T, to name : String) async throws {
        try store(item: item, to: name)
    }

    public func retrieve<T: Decodable>(itemOf type : T.Type, from name : String) throws -> T? {
        if let data = userDefaults.data(forKey: name) {
            return try coder.decode(T.self, from: data)
        }
        return nil
    }

    public func retrieveAsync<T: Decodable>(itemOf type : T.Type, from name : String) async throws -> T? {
        return try retrieve(itemOf: type, from: name)
    }
}
