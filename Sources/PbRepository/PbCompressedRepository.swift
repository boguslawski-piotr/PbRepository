/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

/// Decorator for classes that conforms to the PbRepository / PbRepositoryAsync protocols
/// providing compression of stored items and of course decompression when retrieving.
public struct PbCompressedRepository<Repository>: PbRepositoryDecorator {
    public typealias Repository = Repository

    public let compressorDecompressor: PbCompressorDecompressor
    public let repository: Repository
    public let coder: PbCoder
    
    public init(_ repository: Repository, compressorDecompressor: PbCompressorDecompressor = PbSimpleCompressorDecompressor(), coder: PbCoder = PropertyListCoder()) {
        self.compressorDecompressor = compressorDecompressor
        self.repository = repository
        self.coder = coder
    }

    private func compressingStream<T>(_ sequence: T) throws -> ThrowingStream<Data, Error> where T: Sequence, T.Element: Encodable {
        var sequenceIterator = sequence.makeIterator()
        return ThrowingStream<Data, Error> {
            guard let item = sequenceIterator.next() else { return nil }
            return try self.compressorDecompressor.compress(item, encoder: self.coder)
        }
    }
}

extension PbCompressedRepository where Repository: PbSimpleRepository {
    public func store<T>(item: T, to name: String) throws where T: Encodable {
        try repository.store(item: try compressorDecompressor.compress(item, encoder: coder), to: name)
    }

    public func retrieve<T>(itemOf type: T.Type, from name: String) throws -> T? where T: Decodable {
        guard let edata = try repository.retrieve(itemOf: Data.self, from: name) else { return nil }
        return try compressorDecompressor.decompress(itemOf: type, from: edata, decoder: coder)
    }
}

extension PbCompressedRepository where Repository: PbRepository {
    public func store<T>(sequence: T, to name: String) throws where T: Sequence, T.Element: Encodable {
        try repository.store(sequence: try compressingStream(sequence), to: name)
    }
    
    public func retrieve<T>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? where T: Decodable {
        guard var compressedDataIterator = try repository.retrieve(sequenceOf: Data.self, from: name)?.makeIterator()
        else { return nil }
        return ThrowingStream {
            guard let cdata = try compressedDataIterator.nextThrows() else { return nil }
            return try self.compressorDecompressor.decompress(itemOf: type, from: cdata, decoder: self.coder)
        }
    }
}

extension PbCompressedRepository where Repository: PbSimpleRepositoryAsync {
    public func storeAsync<T>(item: T, to name: String) async throws where T: Encodable {
        try await repository.storeAsync(item: try compressorDecompressor.compress(item, encoder: coder), to: name)
    }

    public func retrieveAsync<T>(itemOf type: T.Type, from name: String) async throws -> T? where T: Decodable {
        guard let edata = try await repository.retrieveAsync(itemOf: Data.self, from: name) else { return nil }
        try Task.checkCancellation()
        return try compressorDecompressor.decompress(itemOf: type, from: edata, decoder: coder)
    }
}

extension PbCompressedRepository where Repository: PbRepositoryAsync {
    public func storeAsync<T>(sequence: T, to name: String) async throws where T: Sequence, T.Element: Encodable {
        try await repository.storeAsync(sequence: try compressingStream(sequence), to: name)
    }

    public func retrieveAsync<T>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? where T: Decodable {
        guard var compressedDataIterator = try await repository.retrieveAsync(sequenceOf: Data.self, from: name)?.makeAsyncIterator()
        else { return nil }
        return AsyncThrowingStream {
            try Task.checkCancellation()
            guard let cdata = try await compressedDataIterator.next() else { return nil }
            return try self.compressorDecompressor.decompress(itemOf: type, from: cdata, decoder: self.coder)
        }
    }
}

extension PbCompressedRepository: PbSimpleRepository where Repository: PbSimpleRepository {}
extension PbCompressedRepository: PbSimpleRepositoryAsync where Repository: PbSimpleRepositoryAsync {}
extension PbCompressedRepository: PbRepository where Repository: PbRepository {}
extension PbCompressedRepository: PbRepositoryAsync where Repository: PbRepositoryAsync {}
