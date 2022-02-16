/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

public protocol PbRepositoryDecorator {
    associatedtype Repository
    var repository: Repository { get }
}

public extension PbRepositoryDecorator where Repository: PbSimpleRepository {
    var name: String { repository.name }
    
    func delete(_ name: String) throws {
        try repository.delete(name)
    }
}

public extension PbRepositoryDecorator where Repository: PbSimpleRepositoryAsync {
    var name: String { repository.name }
    
    func deleteAsync(_ name: String) async throws {
        try await repository.deleteAsync(name)
    }
}

public extension PbRepositoryDecorator where Repository: PbRepository {
    func metadata(for name: String) throws -> PbRepository.ItemMetadata? {
        return try repository.metadata(for: name)
    }
    
    func metadata(forAllMatching isIncluded: @escaping (String) throws -> Bool) throws -> ThrowingStream<PbRepository.ItemMetadata, Error> {
        return try repository.metadata(forAllMatching: isIncluded)
    }
    
    func rename(_ from: String, to: String) throws -> Bool {
        return try repository.rename(from, to: to)
    }
}

public extension PbRepositoryDecorator where Repository: PbRepositoryAsync {
    func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        return try await repository.metadataAsync(for: name)
    }
    
    func metadataAsync(forAllMatching isIncluded: @escaping (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        return try await repository.metadataAsync(forAllMatching: isIncluded)
    }
    
    func renameAsync(_ from: String, to: String) async throws -> Bool {
        return try await repository.renameAsync(from, to: to)
    }
}
