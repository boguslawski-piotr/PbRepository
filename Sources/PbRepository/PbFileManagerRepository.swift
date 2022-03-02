/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import PbEssentials

open class PbFileManagerRepository: PbRepository, PbRepositoryAsync {
    // MARK: Definitions
    
    public struct FileMetadata: PbRepository.ItemMetadata {
        public var name: String
        public var size: Int?
        public var createdOn: Date?
        public var modifiedOn: Date?

        public init(
            _ name: String,
            _ size: Int? = nil,
            _ createdOn: Date? = nil,
            _ modifiedOn: Date? = nil
        ) {
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

    open var name: String

    public let distributingFilesRule: DistributingFilesRules
    public let coder: PbCoder
    public let baseUrl: URL
    public let fileManager: FileManager

    // MARK: Initialization

    public init(
        name: String,
        coder: PbCoder = PropertyListCoder(),
        distributingFilesRule: DistributingFilesRules = .flat,
        baseUrl: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(Bundle.main.name.asPathComponent()),
        fileManager: FileManager = FileManager.default
    ) {
        self.name = name
        self.distributingFilesRule = distributingFilesRule
        self.coder = coder
        self.baseUrl = baseUrl
        self.fileManager = fileManager
    }

    // MARK: Filenames
    
    public func createDirectory(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    open func repositoryUrl() throws -> URL {
        let url = baseUrl.appendingPathComponent(self.name.asPathComponent())
        try createDirectory(at: url)
        return url
    }

    open func fileUrl(_ fileName: String) throws -> URL {
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
        case .custom(let distributor):
            dirName = distributor(fileName)
            break
        }
        
        if !dirName.isEmpty {
            url.appendPathComponent(dirName)
            try createDirectory(at: url)
        }
        return url.appendingPathComponent(fileName)
    }

    // MARK: Implementation
    
    open func metadata(for name: String) throws -> PbRepository.ItemMetadata? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }

        let attrs = try fileManager.attributesOfItem(atPath: fileUrl.path)
        return FileMetadata(
            name,
            attrs[.size] as? Int,
            attrs[.creationDate] as? Date,
            attrs[.modificationDate] as? Date
        )
    }

    open func metadataAsync(for name: String) async throws -> PbRepository.ItemMetadata? {
        try metadata(for: name)
    }

    public func itemNames(matching isIncluded: @escaping (String) throws -> Bool) throws -> [String] {
        var itemNames = [String]()
        if let filesEnumerator = fileManager.enumerator(at: try repositoryUrl(), includingPropertiesForKeys: nil) {
            for case let fileUrl as URL in filesEnumerator {
                if !fileUrl.hasDirectoryPath {
                    let name = fileUrl.lastPathComponent
                    if try isIncluded(name) {
                        itemNames.append(name)
                    }
                }
                try Task.checkCancellation()
            }
        }
        return itemNames
    }

    open func metadata(forAllMatching isIncluded: @escaping (String) throws -> Bool) throws -> ThrowingStream<PbRepository.ItemMetadata, Error>
    {
        var itemNamesIterator = try itemNames(matching: isIncluded).makeIterator()
        return ThrowingStream {
            guard let name = itemNamesIterator.next() else { return nil }
            guard let meta = try self.metadata(for: name) else { return nil }
            return meta
        }
    }

    open func metadataAsync(forAllMatching isIncluded: @escaping (String) throws -> Bool) async throws -> AsyncThrowingStream<PbRepository.ItemMetadata, Error>
    {
        // TODO: Make it more asynchronous: use fileManager.enumerator.nextObject inside AsyncThrowingStream closure.
        var itemNamesIterator = try itemNames(matching: isIncluded).makeIterator()
        return AsyncThrowingStream {
            try Task.checkCancellation()
            guard let name = itemNamesIterator.next() else { return nil }
            guard let meta = try await self.metadataAsync(for: name) else { return nil }
            return meta
        }
    }

    open func store<T: Encodable>(item: T, to name: String) throws {
        let fileUrl = try fileUrl(name)
        let data = try coder.encode(item)
        try data.write(to: fileUrl)
    }

    open func storeAsync<T: Encodable>(item: T, to name: String) async throws {
        try store(item: item, to: name)
    }

    open func store<T: Sequence>(sequence: T, to name: String) throws where T.Element: Encodable {
        try store(item: sequence.map({ $0 }), to: name)
    }

    open func storeAsync<T: Sequence>(sequence: T, to name: String) async throws where T.Element: Encodable {
        try store(sequence: sequence, to: name)
    }

    open func retrieve<T: Decodable>(itemOf type: T.Type, from name: String) throws -> T? {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        let data = try Data(contentsOf: fileUrl)
        return try coder.decode(T.self, from: data)
    }

    open func retrieveAsync<T: Decodable>(itemOf type: T.Type, from name: String) async throws -> T? {
        try retrieve(itemOf: type, from: name)
    }

    open func retrieve<T: Decodable>(sequenceOf type: T.Type, from name: String) throws -> ThrowingStream<T, Error>?
    {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
        return ThrowingStream {
            return iterator.next()
        }
    }

    open func retrieveAsync<T: Decodable>(sequenceOf type: T.Type, from name: String) async throws -> AsyncThrowingStream<T, Error>?
    {
        let fileUrl = try fileUrl(name)
        guard fileManager.fileExists(atPath: fileUrl.path) else { return nil }
        var iterator = try coder.decode([T].self, from: try Data(contentsOf: fileUrl)).makeIterator()
        return AsyncThrowingStream {
            try Task.checkCancellation()
            return iterator.next()
        }
    }

    @discardableResult
    open func rename(_ from: String, to: String) throws -> Bool {
        let fromUrl = try fileUrl(from)
        guard fileManager.fileExists(atPath: fromUrl.path) else { return false }
        let toUrl = try fileUrl(to)
        try fileManager.moveItem(atPath: fromUrl.path, toPath: toUrl.path)
        return true
    }

    @discardableResult
    open func renameAsync(_ from: String, to: String) async throws -> Bool {
        try rename(from, to: to)
    }

    open func delete(_ name: String) throws {
        let fileUrl = try fileUrl(name)
        if fileManager.fileExists(atPath: fileUrl.path) {
            if (try? fileManager.trashItem(at: fileUrl, resultingItemURL: nil)) == nil {
                try fileManager.removeItem(at: fileUrl)
            }
        }
    }

    open func deleteAsync(_ name: String) async throws {
        try delete(name)
    }
}
