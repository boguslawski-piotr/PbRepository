/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing encryption of stored items and of course decryption when retrieving.
open class PbEncryptedRepository: PbRepositoryDecoratorBase, PbRepository, PbRepositoryAsync {
    public private(set) var cipher: PbCipher? = nil

    open func cipher(_ cipher: PbCipher) -> Self {
        self.cipher = cipher
        return self
    }

    // MARK: Store & Retrieve

    open func store<T>(item: T, to name: String) throws where T: Encodable {
        try rS!.store(item: try cipher!.encrypt(item), to: name)
    }

    open func storeAsync<T>(item: T, to name: String) async throws where T: Encodable {
        try await rSA!.storeAsync(item: try cipher!.encrypt(item), to: name)
    }

    open func retrieve<T>(itemOf type: T.Type, from name: String) throws -> T? where T: Decodable {
        guard let edata = try rS!.retrieve(itemOf: Data.self, from: name) else { return nil }
        return try cipher!.decrypt(itemOf: type, from: edata)
    }

    open func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T?
    where T: Decodable {
        guard let edata = try await rSA!.retrieveAsync(itemOf: Data.self, from: name) else { return nil }
        return try cipher!.decrypt(itemOf: type, from: edata)
    }

    private func encryptingStream<T>(_ sequence: T) throws -> ThrowingStream<Data, Error>
    where T: Sequence, T.Element: Encodable {
        var sequenceIterator = sequence.makeIterator()
        return ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.cipher!.encrypt(item)
        }
    }

    open func store<T>(sequence: T, to name: String) throws where T: Sequence, T.Element: Encodable {
        try rF!.store(sequence: try encryptingStream(sequence), to: name)
    }

    open func storeAsync<T>(sequence: T, to name: String) async throws
    where T: Sequence, T.Element: Encodable {
        try await rFA?.storeAsync(sequence: try encryptingStream(sequence), to: name)
    }

    open func retrieve<T>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? where T: Decodable {
        guard var encryptedDataIterator = try rF!.retrieve(sequenceOf: Data.self, from: name)?.makeIterator()
        else { return nil }
        return ThrowingStream {
            guard let edata = try encryptedDataIterator.nextThrows() else { return nil }
            return try self.cipher!.decrypt(itemOf: type, from: edata)
        }
    }

    open func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? where T: Decodable {
        guard var encryptedDataIterator = try await rFA?.retrieveAsync(sequenceOf: Data.self, from: name)?.makeAsyncIterator()
        else { return nil }
        return AsyncThrowingStream {
            guard let edata = try await encryptedDataIterator.next() else { return nil }
            return try self.cipher!.decrypt(itemOf: type, from: edata)
        }
    }
}
