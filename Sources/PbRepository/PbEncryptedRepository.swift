import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing encryption of stored items and of course decrypting when retrieving.
///
/// This class should always be inherited and methods `encrypt(_)`
/// and `decrypt(itemof:from)` should be overridden because default
/// implementation is very trivial and has nothing to do with data encryption :)
open class PbEncryptedRepository : PbRepositoryAsync
{
    public let name : String
    private let repository : PbRepositoryAsync
    
    public init(_ repository: PbRepositoryAsync) {
        self.name = repository.name
        self.repository = repository
    }

    // MARK: Encyption & Decryption
    
    private lazy var encoder = JSONEncoder()
    private lazy var decoder = JSONDecoder()

    /// Should encrypt item of type T into object of type Data.
    open func encrypt<T>(_ item: T) throws -> Data where T : Encodable {
        var data = try encoder.encode(item)
        data.enumerated().forEach { (i, _) in data[i] = ~data[i] }
        return data
    }

    /// Should decrypt data into object of type T.
    open func decrypt<T>(itemOf type: T.Type, from data: Data) throws -> T? where T : Decodable {
        var data = data
        data.enumerated().forEach { (i, _) in data[i] = ~data[i] }
        return try decoder.decode(type, from: data)
    }

    // MARK: Store & Retrieve
    
    public func storeAsync<T>(item: T, to name: String) async throws where T : Encodable {
        try await repository.storeAsync(item: try encrypt(item), to: name)
    }

    public func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T? where T : Decodable {
        guard let edata = try await repository.retrieveAsync(itemOf: Data.self, from: name) else { return nil }
        return try decrypt(itemOf: type, from: edata)
    }

    public func storeAsync<T>(sequence: T, to name: String) async throws where T : Sequence, T.Element : Encodable {
        var sequenceIterator = sequence.makeIterator()
        let edataStream = ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.encrypt(item)
        }
        try await repository.storeAsync(sequence: edataStream, to: name)
    }

    public func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? where T : Decodable {
        guard let edataStream = try await repository.retrieveAsync(sequenceOf: Data.self, from: name) else { return nil }
        var edataIterator = edataStream.makeAsyncIterator()
        return AsyncThrowingStream {
            guard let edata = try await edataIterator.next() else { return nil }
            return try self.decrypt(itemOf: type, from: edata)
        }
    }
    
    // MARK: Pass-through-only functions
    
    public func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        return try await repository.metadataAsync(for: name)
    }
    
    public func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        return try await repository.metadataAsync(forAllMatching: isIncluded)
    }
    
    public func renameAsync(_ from: String, to: String) async throws -> Bool {
        return try await repository.renameAsync(from, to: to)
    }
    
    public func deleteAsync(_ name: String) async throws {
        try await repository.deleteAsync(name)
    }
}
