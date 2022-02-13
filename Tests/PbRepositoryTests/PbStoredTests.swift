import Combine
import Foundation
import XCTest

@testable import PbEssentials
@testable import PbRepository

// MARK: Basic tests

public class PbStoredBasicTest: XCTestCase, PbObservableObject {
    @PbPublished public var ptest = "Initial value"
    @PbStored("Test") public var stest = "Initial value"

    public var c0, c1: AnyCancellable?

    public func test() {
        try? PbUserDefaultsRepository(name: "").delete("Test")

        let test = PbStoredBasicTest()
        dbg(test.stest, "== Initial value")
        XCTAssert(test.stest == "Initial value")
        test.step()
        XCTAssert(test.stest == "New value")

        let test2 = PbStoredBasicTest()
        dbg(test2.stest, "== New value")
        XCTAssert(test2.stest == "New value")
        test2.step()
        XCTAssert(test2.stest == "New value")
    }

    public func step() {
        var changes = 0
        c0 =
            objectWillChange
            .sink {
                dbg("object changed")
                changes += 1
            }

        self.ptest = "New value"
        self.stest = "New value"

        XCTAssert(changes == 2)
    }
}

// MARK: Non trivial test

// Structure:
// Group
//      Name
//      Noteses
//          Name
//          Notes
//              Subject
//              Content

struct Repository {
    static var coder: PbCoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return PbCoderBase(JSONDecoder(), encoder)
    }

    static var repository = PbFileManagerRepository(name: "Notes", coder: Repository.coder)

    static var notesDataRepository = PbStoredRepository.sync(repository)
}

class NotesData: PbObservableObject {
    @PbStored("data", Repository.notesDataRepository) var data = PbObservableArray<Group>()
    @PbStored("test", Repository.notesDataRepository) var test = "Initial value"

    static var notesLoaded = 0
    static var noteLoaded = 0

    class Group: PbObservableObject, Codable {
        @PbPublished var id = UUID()
        @PbPublished var name: String
        @PbPublished var noteses = PbObservableArray<Notes>()

        init(_ name: String) {
            self.name = name
        }

        func createNotes(_ name: String) -> Notes {
            let notes = Notes(name)
            noteses.elements.append(notes)
            return notes
        }
    }

    class Notes: PbObservableObject, Codable, PbStoredProperty {
        func didRetrieve() {
            dbg("Notes didLoad")
            NotesData.notesLoaded += 1
        }

        @PbPublished var id = UUID()
        @PbPublished var name: String
        @PbPublished var notes = PbObservableArray<Note>()

        init(_ name: String) {
            self.name = name
        }

        func createNote(_ subject: String, _ content: String) -> Note {
            let note = Note(subject, content)
            notes.elements.append(note)
            return note
        }
    }

    class Note: PbObservableObject, Codable, PbStoredProperty {
        func didRetrieve() {
            dbg("Note didLoad")
            NotesData.noteLoaded += 1
        }

        @PbPublished var id = UUID()
        @PbPublished var subject: String
        @PbPublished var content: String

        init(_ subject: String, _ content: String) {
            self.subject = subject
            self.content = content
        }
    }

    var subscription: AnyCancellable?

    init() {
        subscription = _data.retrieving.sink { v in
            if !v {
                self.dataDidRetrieve()
                self.subscription = nil
            }
        }
    }

    func dataDidRetrieve() {
        objectDidChange.send()
        dbg("dataDidRetrieve")
    }

    func createGroup(_ name: String) -> Group {
        let group = Group(name)
        data.elements.append(group)
        return group
    }
}

public class NotesApp: XCTestCase {
    var subscription: AnyCancellable?
    var changes = 0
    var changesInCode = 0

    func test() {
        try? Repository.repository.delete("data")
        try? Repository.repository.delete("test")

        let notesData1 = NotesData()
        step(notesData: notesData1, testShouldBe: "Initial value")

        XCTAssert(changes == 12)
        XCTAssert(changes == changesInCode)
        XCTAssert(NotesData.notesLoaded == 0)
        XCTAssert(NotesData.noteLoaded == 0)

        Thread.sleep(forTimeInterval: .seconds(1))

        let notesData2 = NotesData()
        step(notesData: notesData2, testShouldBe: "New value")

        XCTAssert(changes == 15)
        XCTAssert(changes == changesInCode)
        XCTAssert(NotesData.notesLoaded == 1)
        XCTAssert(NotesData.noteLoaded == 3)
    }

    func step(notesData: NotesData, testShouldBe: String) {
        dbg("start!")

        changes = 0
        changesInCode = 0
        subscription = notesData.objectWillChange.sink { [weak self] in
            self?.changes += 1
        }

        //

        XCTAssert(notesData.test == testShouldBe)

        notesData.test = "New value"
        changesInCode += 1

        // Test LOADED data

        if let group = notesData.data.first {
            group.name = "group 1"
            changesInCode += 1
            if let notes = group.noteses.first {
                notes.name = "notes 1"
                changesInCode += 1
                if let note = notes.notes.first {
                    note.subject = "note 1"
                    changesInCode += 1
                }
            }
        }

        // Test NEW data

        notesData.data.elements.removeAll()
        changesInCode += 1

        let group = notesData.createGroup("group 1")
        changesInCode += 1
        let notes = group.createNotes("notes 1")
        changesInCode += 1

        let note1 = notes.createNote("note 1", "content 1")
        note1.content = "modified content 1"
        changesInCode += 1
        changesInCode += 1

        let note2 = notes.createNote("note 2", "content 2")
        note2.content = "modified content 2"
        changesInCode += 1
        changesInCode += 1

        group.name = "modified group 1"
        notes.name = "modified notes 1"
        changesInCode += 1
        changesInCode += 1

        let note3 = notes.createNote("note 3", "content 3")
        note3.content = "modified content 3"
        changesInCode += 1
        changesInCode += 1

        dbg("\(changes) changes == \(changesInCode)")
    }
}
