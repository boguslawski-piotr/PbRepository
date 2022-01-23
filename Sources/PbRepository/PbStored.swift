/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Foundation
import Combine
import PbEssentials

public enum PbStoredRepository
{
    case sync(PbSimpleRepository?)
    case async(PbSimpleRepositoryAsync?, delayStoringBy: TimeInterval = .miliseconds(250))
}

public protocol PbStoredConfiguration
{
    var id : String { get }
    var repository : PbStoredRepository { get }
}

open class PbStoredDefaultConfiguration : PbStoredConfiguration, Identifiable
{
    public static var repository = PbStoredRepository.sync(PbUserDefaultsRepository(name: "", coder: PropertyListCoder()))

    open var id : String
    open var repository : PbStoredRepository

    public init(_ id: String, repository: PbStoredRepository = PbStoredDefaultConfiguration.repository) {
        self.id = id
        self.repository = repository
    }
}

@propertyWrapper
public final class PbStored<Value : Codable> : PbPublishedProperty, PbObservableObject
{
    public enum Status {
        case initializing, retrieving, storing, idle
        case error(Error)
    }
    
    @PbPublished public var status = PbValueWithLock<Status>(Status.initializing)
    @PbPublished public var configuration : PbStoredConfiguration

    public var wrappedValue : Value {
        get { value }
        set { setValue(newValue) }
    }

    public init(wrappedValue: Value, _ configuration: PbStoredConfiguration) {
        self.configuration = configuration
        self.value = wrappedValue
        retrieve()
    }

    public init(wrappedValue: Value, _ configuration: PbStoredConfiguration) where Value: PbStoredProperty {
        self.configuration = configuration
        self.value = wrappedValue
        valueDidRetrieve = { [weak self] in self?.value.didRetrieve() }
        retrieve()
    }

    public init(wrappedValue: Value, _ configuration: PbStoredConfiguration) where Value: PbObservableObject {
        self.configuration = configuration
        self.value = wrappedValue
        valueDidSet = { [weak self] in self?.valueIsAnObservableObject() }
        valueDidSet?()
        retrieve()
    }

    public init(wrappedValue: Value, _ configuration: PbStoredConfiguration) where Value: PbStoredProperty & PbObservableObject {
        self.configuration = configuration
        self.value = wrappedValue
        valueDidRetrieve = { [weak self] in self?.value.didRetrieve() }
        valueDidSet = { [weak self] in self?.valueIsAnObservableObject() }
        valueDidSet?()
        retrieve()
    }

    public convenience init(wrappedValue: Value, _ id: String) {
        self.init(wrappedValue: wrappedValue, PbStoredDefaultConfiguration(id))
    }
    
    public convenience init(wrappedValue: Value, _ id: String) where Value: PbStoredProperty {
        self.init(wrappedValue: wrappedValue, PbStoredDefaultConfiguration(id))
    }

    public convenience init(wrappedValue: Value, _ id: String) where Value: PbObservableObject {
        self.init(wrappedValue: wrappedValue, PbStoredDefaultConfiguration(id))
    }

    public convenience init(wrappedValue: Value, _ id: String) where Value: PbStoredProperty & PbObservableObject {
        self.init(wrappedValue: wrappedValue, PbStoredDefaultConfiguration(id))
    }

    public var parentObjectWillChange : ObservableObjectPublisher?
    public var parentObjectDidChange : ObservableObjectPublisher?

    private var subscriptions : [AnyCancellable?] = [nil,nil,nil]
    private var valueDidRetrieve : (() -> Void)?
    private var valueDidSet : (() -> Void)?
    private var value : Value

    private func valueIsAnObservableObject() where Value : PbObservableObject {
        cancelSubscriptions()
        subscriptions[0] = value.objectDidChange.sink { [weak self] _ in
            self?.store()
        }
        subscriptions[1] = value.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.parentObjectWillChange?.send()
        }
        subscriptions[2] = value.objectDidChange.sink { [weak self] _ in
            self?.objectDidChange.send()
            self?.parentObjectDidChange?.send()
        }
    }

    private func cancelSubscriptions() {
        subscriptions.enumerated().forEach({
            $0.element?.cancel()
            subscriptions[$0.offset] = nil
        })
    }

    deinit {
        cancelSubscriptions()
    }

    private func setValue(_ newValue: Value, andStore: Bool = true) {
        objectWillChange.send()
        parentObjectWillChange?.send()
        value = newValue
        objectDidChange.send()
        parentObjectDidChange?.send()
        valueDidSet?()
        if andStore {
            store()
        }
    }
    
    private func perform(_ code: () throws -> Void) {
        do {
            try code()
            status.value = .idle
        }
        catch {
            status.value = .error(PbError(error))
        }
    }

    private func perform(_ code: () async throws -> Void) async {
        do {
            try await code()
            status.value = .idle
        }
        catch {
            status.value = .error(PbError(error))
        }
    }

    public func retrieve() {
        status.value = .retrieving
        switch configuration.repository
        {
        case .sync(let repository):
            perform {
                if let v = try repository?.retrieve(itemOf: Value.self, from: configuration.id) {
                    setValue(v, andStore: false)
                    valueDidRetrieve?()
                }
            }

        case .async(let repository, _):
            Task(priority: .high) {
                await perform {
//                    try await Task.sleep(for: .seconds(1))
                    if let v = try await repository?.retrieveAsync(itemOf: Value.self, from: configuration.id) {
                        setValue(v, andStore: false)
                        valueDidRetrieve?()
                    }
                }
            }
        }
    }
    
    private var storeTask : Task.NoResultNoError?

    public func store() {
        status.value = .storing
        switch configuration.repository
        {
        case .sync(let repository):
            perform {
                try repository?.store(item: value, to: configuration.id)
            }
            
        case .async(let repository, let delayStoringBy):
            storeTask?.cancel()
            storeTask = Task.delayed(by: delayStoringBy, priority: .low) {
                await perform {
                    try await repository?.storeAsync(item: value, to: configuration.id)
                }
                storeTask = nil
            }
        }
    }
}

// MARK: Extensions

public protocol PbStoredProperty
{
    func didRetrieve()
}

extension PbPublished: PbStoredProperty
{
    public func didRetrieve() {
        if let value = wrappedValue as? PbStoredProperty {
            value.didRetrieve()
        }
    }
}

extension PbObservableCollection
{
    internal func _didRetrieve() {
        cancelSubscriptions()
        for element in elements {
            let objectWillChange = element.objectWillChange
            let objectDidChange = element.objectDidChange
            
            var reflection : Mirror? = Mirror(reflecting: element)
            while let aClass = reflection {
                for (_, property) in aClass.children {
                    if property is PbPublishedProperty {
                        _subscriptions.append(objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
                        _subscriptions.append(objectDidChange.sink { [weak self] _ in self?.objectDidChange.send() })
                    }
                    if let storedProperty = property as? PbStoredProperty {
                        storedProperty.didRetrieve()
                    }
                }
                reflection = aClass.superclassMirror
            }
            
            if let element = element as? PbStoredProperty {
                element.didRetrieve()
            }
        }
    }
}

extension PbObservableArray: PbStoredProperty
{
    public func didRetrieve() {
        _didRetrieve()
    }
}

extension PbObservableSet: PbStoredProperty
{
    public func didRetrieve() {
        _didRetrieve()
    }
}

