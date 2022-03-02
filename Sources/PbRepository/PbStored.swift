/// Swift PbRepository
/// Copyright (c) Piotr Boguslawski
/// MIT license, see License.md file for details.

import Combine
import Foundation
import PbEssentials

public enum PbStoredRepository {
    public static var `default` = PbStoredRepository.sync(
        PbUserDefaultsRepository(name: "", coder: PropertyListCoder())
    )

    case sync(PbSimpleRepository?)
    case async(PbSimpleRepositoryAsync?, delayStoringBy: TimeInterval = .miliseconds(250))
}

// TODO: dodac lock(s), w wielu miejscach w prywatnych skladowych i jako opcje dla value

@propertyWrapper
public final class PbStored<Value: Codable>: PbPublishedProperty, PbObservableObject {
    public lazy var retrieving = AnyPublisher(_retrieving)
    public lazy var storing = AnyPublisher(_storing)

    public var name: String {
        didSet {
            retrieve()
        }
    }
    
    public var lastError: PbError?

    public var wrappedValue: Value {
        get { value }
        set { setValue(newValue) }
    }

    public init(
        wrappedValue: Value,
        _ name: String,
        _ repository: PbStoredRepository? = PbStoredRepository.default
    ) {
        self.repository = repository
        self.name = name
        self.value = wrappedValue
        retrieve()
    }

    public init(
        wrappedValue: Value,
        _ name: String,
        _ repository: PbStoredRepository? = PbStoredRepository.default
    ) where Value: PbStoredProperty {
        self.repository = repository
        self.name = name
        self.value = wrappedValue
        valueDidRetrieve = { [weak self] in self?.value.didRetrieve() }
        retrieve()
    }

    public init(
        wrappedValue: Value,
        _ name: String,
        _ repository: PbStoredRepository? = PbStoredRepository.default
    ) where Value: PbObservableObject {
        self.repository = repository
        self.name = name
        self.value = wrappedValue
        valueDidSet = { [weak self] in self?.subscribeToValue() }
        valueDidSet?()
        retrieve()
    }

    public init(
        wrappedValue: Value,
        _ name: String,
        _ repository: PbStoredRepository? = PbStoredRepository.default
    ) where Value: PbStoredProperty & PbObservableObject {
        self.repository = repository
        self.name = name
        self.value = wrappedValue
        valueDidRetrieve = { [weak self] in self?.value.didRetrieve() }
        valueDidSet = { [weak self] in self?.subscribeToValue() }
        valueDidSet?()
        retrieve()
    }

    public func setValue(_ newValue: Value, andStore: Bool = true) {
        objectWillChange.send()
        _objectWillChange?.send()
        value = newValue
        _objectDidChange?.send()
        objectDidChange.send()
        valueDidSet?()
        if andStore {
            store()
        }
    }
    
    public var _objectWillChange: ObservableObjectPublisher?
    public var _objectDidChange: ObservableObjectPublisher?

    private lazy var _retrieving = CurrentValueSubject<Bool, Never>(false)
    private lazy var _storing = CurrentValueSubject<Bool, Never>(false)

    private var repository: PbStoredRepository?
    @PbWithLock private var storeTask: Task.NoResultCanThrow?
    
    private var subscriptions: [AnyCancellable?] = [nil, nil]
    private var valueDidRetrieve: (() -> Void)?
    private var valueDidSet: (() -> Void)?
    private var value: Value

    private func subscribeToValue() where Value: PbObservableObject {
        cancelSubscriptions()
        subscriptions[0] = value.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?._objectWillChange?.send()
        }
        subscriptions[1] = value.objectDidChange.sink { [weak self] _ in
            self?._objectDidChange?.send()
            self?.objectDidChange.send()
            self?.store()
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

    private func perform(_ code: () throws -> Void) {
        do {
            try code()
        } catch {
            lastError = PbError(error)
        }
    }

    private func perform(_ code: () async throws -> Void) async {
        do {
            try await code()
        } catch {
            lastError = PbError(error)
        }
    }

    public func retrieve(_ repository: PbStoredRepository? = nil) {
        guard !name.isEmpty else { return }
        if repository != nil {
            self.repository = repository
        }
        guard self.repository != nil else {
            return
        }

        _retrieving.send(true)
        lastError = nil
        switch self.repository!
        {
        case .sync(let repository):
            perform {
                if let v = try repository?.retrieve(itemOf: Value.self, from: self.name) {
                    setValue(v, andStore: false)
                    valueDidRetrieve?()
                }
            }
            _retrieving.send(false)

        case .async(let repository, _):
            Task(priority: .high) {
                await perform {
                    //                    try await Task.sleep(for: .seconds(1))
                    if let v = try await repository?.retrieveAsync(itemOf: Value.self, from: self.name) {
                        setValue(v, andStore: false)
                        valueDidRetrieve?()
                    }
                }
                _retrieving.send(false)
            }
        }
    }

    public func store() {
        guard !name.isEmpty else { return }
        guard repository != nil else { return }
        guard _retrieving.value == false else { return }

        _storing.send(true)
        lastError = nil
        switch repository!
        {
        case .sync(let repository):
            perform {
                try repository?.store(item: value, to: name)
            }
            _storing.send(false)

        case .async(let repository, let delayStoringBy):
            storeTask?.cancel()
            storeTask = Task.delayed(by: delayStoringBy, priority: .low) {
                await perform {
                    try await repository?.storeAsync(item: value, to: name)
                }
                storeTask = nil
                _storing.send(false)
            }
        }
    }
}

// MARK: Extensions

public protocol PbStoredProperty {
    func didRetrieve()
}

public extension PbStoredProperty {
    /// Invoke `didRetrieve` for all elements and it's properties that conforms to `PbStoredProperty` protocol.
    func _didRetrieve<Elements: Sequence>(elements: inout Elements) {
        for element in elements {
            var reflection: Mirror? = Mirror(reflecting: element)
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

extension PbPublished: PbStoredProperty {
    public func didRetrieve() {
        if let value = wrappedValue as? PbStoredProperty {
            value.didRetrieve()
        }
    }
}

extension PbObservableCollection: PbStoredProperty {
    public func didRetrieve() {
        _didRetrieve(elements: &_elements)
    }
}

extension PbObservableDictionary: PbStoredProperty {
    public func didRetrieve() {
        _didRetrieve(elements: &_dictionary.values)
    }
}
