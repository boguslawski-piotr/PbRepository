import Foundation
import PbEssentials

public protocol PbSimpleRepository
{
    var name : String { get }
    func delete(_ name: String) throws
    func store<T: Encodable>(item: T, to name: String) throws
    func retrieve<T: Decodable>(itemOf type: T.Type, from name: String) throws -> T?
}

public protocol PbSimpleRepositoryAsync
{
    var name : String { get }
    func deleteAsync(_ name: String) async throws
    func storeAsync<T: Encodable>(item: T, to name: String) async throws
    func retrieveAsync<T: Decodable>(itemOf type: T.Type, from name: String) async throws -> T?
}

public protocol StoredItemMetadata : Codable
{
    var name : String { get }
    var size : Int? { get }
    var createdOn : Date? { get }
    var modifiedOn : Date? { get }
}

public protocol PbRepository : PbSimpleRepository
{
    typealias ItemMetadata = StoredItemMetadata
    
    func metadata(for name: String) throws -> ItemMetadata?
    func metadata(forAllMatching isIncluded: (String) throws -> Bool) throws -> ThrowingStream<ItemMetadata, Error>

    func rename(_ from: String, to: String) throws -> Bool

    func store<T: Sequence>(sequence: T, to name: String) throws where T.Element : Encodable
    func retrieve<T: Decodable>(sequenceOf type: T.Type, from name: String) async throws -> ThrowingStream<T, Error>?
}

public protocol PbRepositoryAsync : PbSimpleRepositoryAsync
{
    typealias ItemMetadata = StoredItemMetadata

    func metadataAsync(for name: String) async throws -> ItemMetadata?
    func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<ItemMetadata, Error>
    
    func renameAsync(_ from: String, to: String) async throws -> Bool

    func storeAsync<T: Sequence>(sequence: T, to name: String) async throws where T.Element : Encodable
    func retrieveAsync<T: Decodable>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>?
}
