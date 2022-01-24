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
    var repository : PbStoredRepository { get }
    var id : String { get }
}

@propertyWrapper
public final class PbStored<Value: Codable> : PbPublishedProperty
{
    open class DefaultConfiguration : PbStoredConfiguration, Identifiable
    {
        open lazy var repository = PbStoredRepository.sync(PbUserDefaultsRepository(name: "", coder: PropertyListCoder()))
        open var id : String

        public init(_ id: String)
        {
            self.id = id
        }
    }

    public lazy var retrieving = AnyPublisher(_retrieving)
    public lazy var storing = AnyPublisher(_storing)
    
    public var lastError : PbError?

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
        valueDidSet = { [weak self] in self?.subscribeToValue() }
        valueDidSet?()
        retrieve()
    }

    public init(wrappedValue: Value, _ configuration: PbStoredConfiguration) where Value: PbStoredProperty & PbObservableObject {
        self.configuration = configuration
        self.value = wrappedValue
        valueDidRetrieve = { [weak self] in self?.value.didRetrieve() }
        valueDidSet = { [weak self] in self?.subscribeToValue() }
        valueDidSet?()
        retrieve()
    }

    public convenience init(wrappedValue: Value, _ id: String) {
        self.init(wrappedValue: wrappedValue, DefaultConfiguration(id))
    }
    
    public convenience init(wrappedValue: Value, _ id: String) where Value: PbStoredProperty {
        self.init(wrappedValue: wrappedValue, DefaultConfiguration(id))
    }

    public convenience init(wrappedValue: Value, _ id: String) where Value: PbObservableObject {
        self.init(wrappedValue: wrappedValue, DefaultConfiguration(id))
    }

    public convenience init(wrappedValue: Value, _ id: String) where Value: PbStoredProperty & PbObservableObject {
        self.init(wrappedValue: wrappedValue, DefaultConfiguration(id))
    }

    public var _objectWillChange : ObservableObjectPublisher?
    public var _objectDidChange : ObservableObjectPublisher?

    private let configuration : PbStoredConfiguration
    private var storeTask : Task.NoResultNoError?

    private lazy var _retrieving = CurrentValueSubject<Bool, Never>(true)
    private lazy var _storing = CurrentValueSubject<Bool, Never>(false)

    private var subscriptions : [AnyCancellable?] = [nil,nil,nil]
    private var valueDidRetrieve : (() -> Void)?
    private var valueDidSet : (() -> Void)?
    private var value : Value

    private func subscribeToValue() where Value : PbObservableObject {
        cancelSubscriptions()
        subscriptions[0] = value.objectDidChange.sink { [weak self] _ in
            self?.store()
        }
        subscriptions[1] = value.objectWillChange.sink { [weak self] _ in
            self?._objectWillChange?.send()
        }
        subscriptions[2] = value.objectDidChange.sink { [weak self] _ in
            self?._objectDidChange?.send()
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
        _objectWillChange?.send()
        value = newValue
        _objectDidChange?.send()
        valueDidSet?()
        if andStore {
            store()
        }
    }
    
    private func perform(_ code: () throws -> Void) {
        do {
            try code()
        }
        catch {
            lastError = PbError(error)
        }
    }

    private func perform(_ code: () async throws -> Void) async {
        do {
            try await code()
        }
        catch {
            lastError = PbError(error)
        }
    }

    public func retrieve() {
        _retrieving.send(true)
        lastError = nil
        switch configuration.repository
        {
        case .sync(let repository):
            perform {
                if let v = try repository?.retrieve(itemOf: Value.self, from: configuration.id) {
                    setValue(v, andStore: false)
                    valueDidRetrieve?()
                }
            }
            _retrieving.send(false)

        case .async(let repository, _):
            Task(priority: .high) {
                await perform {
//                    try await Task.sleep(for: .seconds(1))
                    if let v = try await repository?.retrieveAsync(itemOf: Value.self, from: configuration.id) {
                        setValue(v, andStore: false)
                        valueDidRetrieve?()
                    }
                }
                _retrieving.send(false)
            }
        }
    }
    
    public func store() {
        _storing.send(true)
        lastError = nil
        switch configuration.repository
        {
        case .sync(let repository):
            perform {
                try repository?.store(item: value, to: configuration.id)
            }
            _storing.send(false)

        case .async(let repository, let delayStoringBy):
            storeTask?.cancel()
            storeTask = Task.delayed(by: delayStoringBy, priority: .low) {
                await perform {
                    try await repository?.storeAsync(item: value, to: configuration.id)
                }
                storeTask = nil
                _storing.send(false)
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
    /**
    Method called after contents of `ObservableCollection` was retrieved from some storage (see `PbStored.retrieve`).
    Invoke `didRetrieve` for all elements and it's properties that are declared as `PbStoredProperty`.
    */
    internal func _didRetrieve() {
        for element in elements {
            var reflection : Mirror? = Mirror(reflecting: element)
            while let aClass = reflection {
                for (_, property) in aClass.children {
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

