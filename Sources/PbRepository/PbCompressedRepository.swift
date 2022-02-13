/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing compression of stored items and of course decompression when retrieving.
open class PbCompressedRepository: PbRepositoryDecoratorBase, PbRepository, PbRepositoryAsync {
    public private(set) var archiver: PbArchiver? = nil

    open func archiver(_ archiver: PbArchiver) -> Self {
        self.archiver = archiver
        return self
    }

    // MARK: Store & Retrieve

    open func store<T>(item: T, to name: String) throws where T: Encodable {
        try rS!.store(item: try archiver!.compress(item), to: name)
    }

    open func storeAsync<T>(item: T, to name: String) async throws where T: Encodable {
        try await rSA!.storeAsync(item: try archiver!.compress(item), to: name)
    }

    open func retrieve<T>(itemOf type: T.Type, from name: String) throws -> T? where T: Decodable {
        guard let edata = try rS!.retrieve(itemOf: Data.self, from: name) else { return nil }
        return try archiver!.decompress(itemOf: type, from: edata)
    }

    open func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T?
    where T: Decodable {
        guard let edata = try await rSA!.retrieveAsync(itemOf: Data.self, from: name) else {
            return nil
        }
        return try archiver!.decompress(itemOf: type, from: edata)
    }

    private func compressingStream<T>(_ sequence: T) throws -> ThrowingStream<Data, Error>
    where T: Sequence, T.Element: Encodable {
        var sequenceIterator = sequence.makeIterator()
        return ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.archiver!.compress(item)
        }
    }

    open func store<T>(sequence: T, to name: String) throws where T: Sequence, T.Element: Encodable {
        try rF!.store(sequence: try compressingStream(sequence), to: name)
    }

    open func storeAsync<T>(sequence: T, to name: String) async throws
    where T: Sequence, T.Element: Encodable {
        try await rFA?.storeAsync(sequence: try compressingStream(sequence), to: name)
    }

    open func retrieve<T>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<
        T, Error
    >? where T: Decodable {
        guard
            var compressedDataIterator = try rF!.retrieve(sequenceOf: Data.self, from: name)?
                .makeIterator()
        else { return nil }
        return ThrowingStream {
            guard let cdata = try compressedDataIterator.nextThrows() else { return nil }
            return try self.archiver!.decompress(itemOf: type, from: cdata)
        }
    }

    open func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws
        -> AsyncThrowingStream<T, Error>? where T: Decodable
    {
        guard
            var compressedDataIterator = try await rFA?.retrieveAsync(sequenceOf: Data.self, from: name)?
                .makeAsyncIterator()
        else { return nil }
        return AsyncThrowingStream {
            guard let cdata = try await compressedDataIterator.next() else { return nil }
            return try self.archiver!.decompress(itemOf: type, from: cdata)
        }
    }
}
