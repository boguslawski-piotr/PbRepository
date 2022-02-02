/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import System
import Foundation
import PbEssentials

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
final public class PbFileManagerRepository : PbRepository, PbRepositoryAsync
{
    public struct FileMetadata : PbRepository.ItemMetadata
    {
        public var name : String
        public var size : Int?
        public var createdOn : Date?
        public var modifiedOn : Date?

        public init(_ name: String, _ size: Int? = nil, _ createdOn: Date? = nil, _ modifiedOn: Date? = nil) {
            self.name = name
            self.size = size
            self.createdOn = createdOn
            self.modifiedOn = modifiedOn
        }
    }

    public private(set) var name : String

    private let baseUrl : URL
    private let coder : PbCoder
    private let archiver : PbArchiver?
    private let fileManager : FileManager

    public init(
        name: String,
        coder: PbCoder? = nil,
        archiver : PbArchiver? = nil,
        baseUrl: URL? = nil,
        fileManager: FileManager? = nil
    ) {
        self.name = name
        self.coder = coder ?? PropertyListCoder()
        self.archiver = archiver
        
        let fileManager = fileManager ?? FileManager.default
        var url = URL(fileURLWithPath: NSHomeDirectory())
        url.appendPathComponent(Bundle.main.name)
        self.baseUrl = baseUrl ?? url
        self.fileManager = fileManager
    }
    
    private func repositoryUrl() throws -> URL {
        var url = baseUrl
        url.appendPathComponent(self.name)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    private func fileUrl(_ fileName: String) throws -> URL {
        var url = try repositoryUrl()
        url.appendPathComponent(fileName)
        return url
    }
    
    public func metadata(for name: String) throws -> PbRepository.ItemMetadata? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }

        let attrs = try fileManager.attributesOfItem(atPath: fileUrl.path)
        return FileMetadata(name, attrs[.size] as? Int, attrs[.creationDate] as? Date, attrs[.modificationDate] as? Date)
    }
    
    public func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        try metadata(for: name)
    }
    
    public func metadata(forAllMatching isIncluded: (String) throws -> Bool) throws -> ThrowingStream<PbRepository.ItemMetadata, Error> {
        var itemNames = try fileManager.contentsOfDirectory(atPath: try repositoryUrl().path).filter({ try isIncluded($0) }).makeIterator()
        return ThrowingStream {
            guard let name = itemNames.next() else { return nil }
            guard let meta = try self.metadata(for: name) else { throw Errno.noSuchFileOrDirectory }
            return meta
        }
    }

    public func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        var itemNames = try fileManager.contentsOfDirectory(atPath: try repositoryUrl().path).filter({ try isIncluded($0) }).makeIterator()
        return AsyncThrowingStream {
            guard let name = itemNames.next() else { return nil }
            guard let meta = try await self.metadataAsync(for: name) else { throw Errno.noSuchFileOrDirectory }
            return meta
        }
    }
    
    public func store<T: Encodable>(item: T, to name: String) throws {
        let fileUrl = try fileUrl(name)
        let data = try coder.encode(item)
        try data.write(to: fileUrl, compressor: archiver?.makeCompressor())
    }
    
    public func storeAsync<T: Encodable>(item: T, to name: String) async throws {
        try store(item: item, to: name)
    }
    
    public func store<T: Sequence>(sequence: T, to name: String) throws where T.Element: Encodable {
        let fileUrl = try fileUrl(name)
        if archiver == nil {
            try store(item: sequence.map({$0}), to: name)
        }
        else {
            var cf = archiver!.makeCompressor()
            try cf.create(file: fileUrl.path, permissions: nil)
            try sequence.forEach({ element in try cf.append(data: try coder.encode(element), withName: nil) })
            try cf.close()
        }
    }
    
    public func storeAsync<T: Sequence>(sequence: T, to name: String) async throws where T.Element: Encodable {
        try store(sequence: sequence, to: name)
    }
    
    public func retrieve<T: Decodable>(itemOf type: T.Type, from name: String) throws -> T? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        
        let data = try Data(contentsOf: fileUrl, decompressor: archiver?.makeDecompressor())
        return try coder.decode(T.self, from: data)
    }
    
    public func retrieveAsync<T: Decodable>(itemOf type: T.Type, from name: String) async throws -> T? {
        try retrieve(itemOf: type, from: name)
    }
    
    public func retrieve<T: Decodable>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        
        if archiver == nil {
            var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
            return ThrowingStream {
                return iterator.next()
            }
        }
        else {
            var df = archiver!.makeDecompressor()
            try df.open(file: fileUrl.path, permissions: nil)
            return ThrowingStream {
                guard let data = try df.read() else {
                    try df.close()
                    return nil
                }
                return try self.coder.decode(T.self, from: data)
            }
        }
    }

    public func retrieveAsync<T: Decodable>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }

        if archiver == nil {
            var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
            return AsyncThrowingStream {
                try Task.checkCancellation()
                return iterator.next()
            }
        }
        else {
            var df = archiver!.makeDecompressor()
            try df.open(file: fileUrl.path, permissions: nil)
            return AsyncThrowingStream {
                try Task.checkCancellation()
                guard let data = try df.read() else {
                    try df.close()
                    return nil
                }
                return try self.coder.decode(T.self, from: data)
            }
        }
    }
    
    public func rename(_ from: String, to: String) throws -> Bool {
        let fromUrl = try fileUrl(from)
        guard fileManager.fileExists(atPath: fromUrl.path) else { return false }
        let toUrl = try fileUrl(to)
        try fileManager.moveItem(atPath: fromUrl.path, toPath: toUrl.path)
        return true
    }
    
    public func renameAsync(_ from: String, to: String) async throws -> Bool {
        try rename(from, to: to)
    }
    
    public func delete(_ name: String) throws {
        let fileUrl = try fileUrl(name)
        if fileManager.fileExists(atPath: fileUrl.path) {
            try fileManager.trashItem(at: fileUrl, resultingItemURL: nil)
        }
    }
    
    public func deleteAsync(_ name: String) async throws {
        try delete(name)
    }
}
