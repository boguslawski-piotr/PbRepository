import XCTest
import Combine
@testable import PbEssentials
@testable import PbRepository

final class PbRepositoryTests: XCTestCase
{
    func testExample() throws {
    }
}

public class PbStoredBasicTest: XCTestCase, PbObservableObject
{
    @PbPublished public var ptest = "Initial value"
    @PbStored("Test") public var stest = "Initial value"
    
    public var c0, c1 : AnyCancellable?
    
    public func go() {
        c1 = _stest.objectDidChange
            .sink {
                dbg("stest changed")
            }
        c0 = objectWillChange
            .sink {
                dbg("object changed")
            }
        
        self.ptest = "New value"
        self.stest = "New value"
    }
    
    public func test() {
        try? PbUserDefaultsRepository(name: "").delete("Test")
        
        let test = PbStoredBasicTest()
        dbg(test.stest, "== Initial value")
        XCTAssert(test.stest == "Initial value")
        test.go()
        XCTAssert(test.stest == "New value")

        let test2 = PbStoredBasicTest()
        dbg(test2.stest, "== New value")
        XCTAssert(test2.stest == "New value")
        test2.go()
        XCTAssert(test2.stest == "New value")
    }
}

