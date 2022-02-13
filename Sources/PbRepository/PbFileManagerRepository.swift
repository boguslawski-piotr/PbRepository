/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

final public class PbFileManagerRepository : PbRepository, PbRepositoryAsync
{
    public struct FileMetadata : PbRepository.ItemMetadata {
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

    public enum DistributingFilesRules {
        case custom(distributor: (String) -> String)
        case flat,
             firstCharacter,
             lastCharacter
    }
    
    public private(set) var name : String

    private let distributingFilesRule : DistributingFilesRules
    private let coder : PbCoder
    private let baseUrl : URL
    private let fileManager : FileManager

    public init(
        name: String,
        distributingFilesRule: DistributingFilesRules = .flat,
        coder: PbCoder? = nil,
        baseUrl: URL? = nil,
        fileManager: FileManager? = nil
    ) {
        self.name = name
        self.distributingFilesRule = distributingFilesRule
        self.coder = coder ?? PropertyListCoder()
        self.baseUrl = baseUrl ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(Bundle.main.name.asPathComponent())
        self.fileManager = fileManager ?? FileManager.default
    }
    
    private func createDirectory(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    public func repositoryUrl() throws -> URL {
        let url = baseUrl.appendingPathComponent(self.name.asPathComponent())
        try createDirectory(at: url)
        return url
    }
    
    public func fileUrl(_ fileName: String) throws -> URL {
        let fileName = fileName.asPathComponent()
        var url = try repositoryUrl()
        var dirName = ""

        switch distributingFilesRule {
        case .flat:
            break
        case .firstCharacter:
            dirName = fileName.first != nil ? String(fileName.first!) : ""
        case .lastCharacter:
            dirName = fileName.last != nil ? String(fileName.last!) : ""
        case .custom(distributor: let distributor):
            dirName = distributor(fileName)
            break
        }

        if !dirName.isEmpty {
            url.appendPathComponent(dirName)
            try createDirectory(at: url)
        }
        return url.appendingPathComponent(fileName)
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
        var itemNames = try fileManager.contentsOfDirectory(atPath: try repositoryUrl().path).lazy.filter({ try isIncluded($0) }).makeIterator()
        return ThrowingStream {
            guard let name = itemNames.next() else { return nil }
            guard let meta = try self.metadata(for: name) else { return nil }
            return meta
        }
    }

    public func metadataAsync(forAllMatching isIncluded: (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error> {
        var itemNames = try fileManager.contentsOfDirectory(atPath: try repositoryUrl().path).lazy.filter({ try isIncluded($0) }).makeIterator()
        return AsyncThrowingStream {
            guard let name = itemNames.next() else { return nil }
            guard let meta = try await self.metadataAsync(for: name) else { return nil }
            return meta
        }
    }
    
    public func store<T: Encodable>(item: T, to name: String) throws {
        let fileUrl = try fileUrl(name)
        let data = try coder.encode(item)
        try data.write(to: fileUrl)
    }
    
    public func storeAsync<T: Encodable>(item: T, to name: String) async throws {
        try store(item: item, to: name)
    }
    
    public func store<T: Sequence>(sequence: T, to name: String) throws where T.Element: Encodable {
        try store(item: sequence.map({$0}), to: name)
    }
    
    public func storeAsync<T: Sequence>(sequence: T, to name: String) async throws where T.Element: Encodable {
        try store(sequence: sequence, to: name)
    }
    
    public func retrieve<T: Decodable>(itemOf type: T.Type, from name: String) throws -> T? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        let data = try Data(contentsOf: fileUrl)
        return try coder.decode(T.self, from: data)
    }
    
    public func retrieveAsync<T: Decodable>(itemOf type: T.Type, from name: String) async throws -> T? {
        try retrieve(itemOf: type, from: name)
    }
    
    public func retrieve<T: Decodable>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
        return ThrowingStream {
            return iterator.next()
        }
    }

    public func retrieveAsync<T: Decodable>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
        return AsyncThrowingStream {
            try Task.checkCancellation()
            return iterator.next()
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
            if (try? fileManager.trashItem(at: fileUrl, resultingItemURL: nil)) == nil {
                try fileManager.removeItem(at: fileUrl)
            }
        }
    }
    
    public func deleteAsync(_ name: String) async throws {
        try delete(name)
    }
}
