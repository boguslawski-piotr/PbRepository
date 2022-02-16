/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing encryption of stored items and of course decryption when retrieving.
public struct PbEncryptedRepository<Repository>: PbRepositoryDecorator {
    public typealias Repository = Repository

    public let cipher: PbCipher
    public let repository: Repository
    public let coder: PbCoder

    public init(_ repository: Repository, cipher: PbCipher, coder: PbCoder = PropertyListCoder()) {
        self.cipher = cipher
        self.repository = repository
        self.coder = coder
    }

    private func encryptingStream<T>(_ sequence: T) throws -> ThrowingStream<Data, Error> where T: Sequence, T.Element: Encodable {
        var sequenceIterator = sequence.makeIterator()
        return ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.cipher.encrypt(item, encoder: self.coder)
        }
    }
}

extension PbEncryptedRepository where Repository: PbSimpleRepository {
    public func store<T>(item: T, to name: String) throws where T: Encodable {
        try repository.store(item: try cipher.encrypt(item, encoder: coder), to: name)
    }

    public func retrieve<T>(itemOf type: T.Type, from name: String) throws -> T? where T: Decodable {
        guard let edata = try repository.retrieve(itemOf: Data.self, from: name) else { return nil }
        return try cipher.decrypt(itemOf: type, from: edata, decoder: coder)
    }
}

extension PbEncryptedRepository where Repository: PbRepository {
    public func store<T>(sequence: T, to name: String) throws where T: Sequence, T.Element: Encodable {
        try repository.store(sequence: try encryptingStream(sequence), to: name)
    }

    public func retrieve<T>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? where T: Decodable {
        guard var encryptedDataIterator = try repository.retrieve(sequenceOf: Data.self, from: name)?.makeIterator()
        else { return nil }
        return ThrowingStream {
            guard let edata = try encryptedDataIterator.nextThrows() else { return nil }
            return try self.cipher.decrypt(itemOf: type, from: edata, decoder: self.coder)
        }
    }
}

extension PbEncryptedRepository where Repository: PbSimpleRepositoryAsync {
    public func storeAsync<T>(item: T, to name: String) async throws where T: Encodable {
        try await repository.storeAsync(item: try cipher.encrypt(item, encoder: coder), to: name)
    }
    
    public func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T?
    where T: Decodable {
        guard let edata = try await repository.retrieveAsync(itemOf: Data.self, from: name) else { return nil }
        try Task.checkCancellation()
        return try cipher.decrypt(itemOf: type, from: edata, decoder: coder)
    }
}

extension PbEncryptedRepository where Repository: PbRepositoryAsync {
    public func storeAsync<T>(sequence: T, to name: String) async throws
    where T: Sequence, T.Element: Encodable {
        try await repository.storeAsync(sequence: try encryptingStream(sequence), to: name)
    }

    public func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? where T: Decodable {
        guard var encryptedDataIterator = try await repository.retrieveAsync(sequenceOf: Data.self, from: name)?.makeAsyncIterator()
        else { return nil }
        return AsyncThrowingStream {
            try Task.checkCancellation()
            guard let edata = try await encryptedDataIterator.next() else { return nil }
            return try self.cipher.decrypt(itemOf: type, from: edata, decoder: self.coder)
        }
    }
}

extension PbEncryptedRepository: PbSimpleRepository where Repository: PbSimpleRepository {}
extension PbEncryptedRepository: PbSimpleRepositoryAsync where Repository: PbSimpleRepositoryAsync {}
extension PbEncryptedRepository: PbRepository where Repository: PbRepository {}
extension PbEncryptedRepository: PbRepositoryAsync where Repository: PbRepositoryAsync {}
