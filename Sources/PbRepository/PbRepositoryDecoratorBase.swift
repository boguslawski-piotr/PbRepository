/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

open class PbRepositoryDecoratorBase
{
    // MARK: Initialization with underlying repository
    
    public var name : String { rS?.name ?? rSA?.name ?? "" }
    
    public private(set) var rS : PbSimpleRepository?
    public private(set) var rF : PbRepository?
    public private(set) var rSA : PbSimpleRepositoryAsync?
    public private(set) var rFA : PbRepositoryAsync?
    
    public init(_ repository: PbSimpleRepository) {
        self.rS = repository
    }
    
    public init(_ repository: PbRepository) {
        self.rS = repository
        self.rF = repository
    }
    
    public init(async repository: PbSimpleRepositoryAsync) {
        self.rSA = repository
    }
    
    public init(async repository: PbRepositoryAsync) {
        self.rSA = repository
        self.rFA = repository
    }
    
    // MARK: Pass-through-only functions
    
    open func metadata(for name: String) throws -> PbRepository.ItemMetadata? {
        return try rF!.metadata(for: name)
    }
    
    open func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        return try await rFA!.metadataAsync(for: name)
    }
    
    open func metadata(forAllMatching isIncluded: (String) throws -> Bool) throws -> ThrowingStream<PbRepository.ItemMetadata, Error> {
        return try rF!.metadata(forAllMatching: isIncluded)
    }
    
    open func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        return try await rFA!.metadataAsync(forAllMatching: isIncluded)
    }
    
    public func rename(_ from: String, to: String) throws -> Bool {
        return try rF!.rename(from, to: to)
    }
    
    open func renameAsync(_ from: String, to: String) async throws -> Bool {
        return try await rFA!.renameAsync(from, to: to)
    }
    
    open func delete(_ name: String) throws {
        try rS!.delete(name)
    }
    
    open func deleteAsync(_ name: String) async throws {
        try await rSA!.deleteAsync(name)
    }
}
