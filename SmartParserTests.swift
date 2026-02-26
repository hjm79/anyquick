import XCTest
@testable import AnyQuick

final class SmartParserTests: XCTestCase {
    func testMessageUsesDynamicContacts() {
        let parser = SmartParser(contacts: ["엄마", "김철수"])
        let intent = parser.parse(input: "김철수한테 문자 보내줘")

        guard case .sendMessage(let targetName, let message, _) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "김철수")
        XCTAssertFalse(message.isEmpty)
    }

    func testMessagePrefersLongestContactName() {
        let parser = SmartParser(contacts: ["철수", "김철수"])
        let intent = parser.parse(input: "김철수에게 안부 보내줘")

        guard case .sendMessage(let targetName, _, _) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "김철수")
    }

    func testMessageDoesNotMatchInsideAnotherWord() {
        let parser = SmartParser(contacts: ["김철수"])
        let intent = parser.parse(input: "김철수학원 검색")

        switch intent {
        case .sendMessage:
            XCTFail("Should not match contact inside another word")
        case .webSearch(let query, let type):
            XCTAssertEqual(type, .naver)
            XCTAssertTrue(query.contains("김철수학원"))
        default:
            XCTFail("Expected webSearch fallback")
        }
    }

    func testContactsCanBeUpdatedAtRuntime() {
        let parser = SmartParser(contacts: [])
        parser.contacts = ["여자친구"]

        let intent = parser.parse(input: "여자친구한테 보고 보내줘")
        guard case .sendMessage(let targetName, _, _) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }
        XCTAssertEqual(targetName, "여자친구")
    }
}
