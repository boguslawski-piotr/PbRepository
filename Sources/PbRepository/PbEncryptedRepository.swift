/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing encryption of stored items and of course decrypting when retrieving.
open class PbEncryptedRepository : PbRepository, PbRepositoryAsync
{
    // MARK: Initialization with underlying repository and some cipher
    
    public let name : String
    private var cipher : PbCipher

    private var rS : PbSimpleRepository?
    private var rF : PbRepository?
    private var rSA : PbSimpleRepositoryAsync?
    private var rFA : PbRepositoryAsync?
    
    public init(_ repository: PbSimpleRepository, cipher: PbCipher) {
        self.name = repository.name
        self.cipher = cipher
        self.rS = repository
    }

    public init(_ repository: PbRepository, cipher: PbCipher) {
        self.name = repository.name
        self.cipher = cipher
        self.rS = repository
        self.rF = repository
    }

    public init(async repository: PbSimpleRepositoryAsync, cipher: PbCipher) {
        self.name = repository.name
        self.cipher = cipher
        self.rSA = repository
    }

    public init(async repository: PbRepositoryAsync, cipher: PbCipher) {
        self.name = repository.name
        self.cipher = cipher
        self.rSA = repository
        self.rFA = repository
    }

    // MARK: Store & Retrieve
    
    public func store<T>(item: T, to name: String) throws where T : Encodable {
        assert(rS != nil)
        try rS!.store(item: try cipher.encrypt(item), to: name)
    }

    public func storeAsync<T>(item: T, to name: String) async throws where T : Encodable {
        assert(rSA != nil)
        try await rSA!.storeAsync(item: try cipher.encrypt(item), to: name)
    }

    public func retrieve<T>(itemOf type: T.Type, from name: String) throws -> T? where T : Decodable {
        assert(rS != nil)
        guard let edata = try rS!.retrieve(itemOf: Data.self, from: name) else { return nil }
        return try cipher.decrypt(itemOf: type, from: edata)
    }

    public func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T? where T : Decodable {
        assert(rSA != nil)
        guard let edata = try await rSA!.retrieveAsync(itemOf: Data.self, from: name) else { return nil }
        return try cipher.decrypt(itemOf: type, from: edata)
    }

    private func edataStream<T>(_ sequence: T) throws -> ThrowingStream<Data, Error> where T : Sequence, T.Element : Encodable {
        var sequenceIterator = sequence.makeIterator()
        return ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.cipher.encrypt(item)
        }
    }

    public func store<T>(sequence: T, to name: String) throws where T : Sequence, T.Element : Encodable {
        assert(rF != nil)
        try rF!.store(sequence: try edataStream(sequence), to: name)
    }

    public func storeAsync<T>(sequence: T, to name: String) async throws where T : Sequence, T.Element : Encodable {
        assert(rFA != nil)
        try await rFA?.storeAsync(sequence: try edataStream(sequence), to: name)
    }

    public func retrieve<T>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? where T : Decodable {
        assert(rF != nil)
        guard let edataStream = try rF!.retrieve(sequenceOf: Data.self, from: name) else { return nil }
        var edataIterator = edataStream.makeIterator()
        return ThrowingStream {
            guard let edata = try edataIterator.nextThrows() else { return nil }
            return try self.cipher.decrypt(itemOf: type, from: edata)
        }
    }
    
    public func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? where T : Decodable {
        assert(rFA != nil)
        guard let edataStream = try await rFA?.retrieveAsync(sequenceOf: Data.self, from: name) else { return nil }
        var edataIterator = edataStream.makeAsyncIterator()
        return AsyncThrowingStream {
            guard let edata = try await edataIterator.next() else { return nil }
            return try self.cipher.decrypt(itemOf: type, from: edata)
        }
    }
    
    // MARK: Pass-through-only functions
    
    public func metadata(for name: String) throws -> PbRepository.ItemMetadata? {
        assert(rF != nil)
        return try rF!.metadata(for: name)
    }

    public func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        assert(rFA != nil)
        return try await rFA!.metadataAsync(for: name)
    }
    
    public func metadata(forAllMatching isIncluded: (String) throws -> Bool) throws -> ThrowingStream<PbRepository.ItemMetadata, Error> {
        assert(rF != nil)
        return try rF!.metadata(forAllMatching: isIncluded)
    }

    public func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        assert(rFA != nil)
        return try await rFA!.metadataAsync(forAllMatching: isIncluded)
    }
    
    public func rename(_ from: String, to: String) throws -> Bool {
        assert(rF != nil)
        return try rF!.rename(from, to: to)
    }

    public func renameAsync(_ from: String, to: String) async throws -> Bool {
        assert(rFA != nil)
        return try await rFA!.renameAsync(from, to: to)
    }
    
    public func delete(_ name: String) throws {
        assert(rS != nil)
        try rS!.delete(name)
    }

    public func deleteAsync(_ name: String) async throws {
        assert(rSA != nil)
        try await rSA!.deleteAsync(name)
    }
}
