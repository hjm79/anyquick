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

    func testContactSelectionContextForRecipientParticle() {
        let parser = SmartParser(contacts: ["정만", "정만수", "홍길동"])
        let context = parser.contactSelectionContext(input: "정만에게 회의자료 보내줘")

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.keyword, "정만")
        XCTAssertEqual(context?.candidates.first, "정만")
        XCTAssertTrue(context?.message.contains("회의자료") == true)
    }

    func testContactSelectionContextIncludesCurrentLocationFlag() {
        let parser = SmartParser(contacts: ["정만"])
        let context = parser.contactSelectionContext(input: "정만에게 현위치 보내줘")

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.isCurrentLocation, true)
    }

    func testMessageDetectsCurrentLocationWithSpace() {
        let parser = SmartParser(contacts: ["정만"])
        let intent = parser.parse(input: "정만에게 현재 위치 보내줘")

        guard case .sendMessage(let targetName, _, let isCurrentLocation) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "정만")
        XCTAssertTrue(isCurrentLocation)
    }

    func testLocationShareCommandWithoutContactUsesSendMessageIntent() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "현재위치 카톡 보내기")

        guard case .sendMessage(let targetName, let message, let isCurrentLocation) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "")
        XCTAssertEqual(message, "")
        XCTAssertTrue(isCurrentLocation)
    }

    func testLocationShareCommandWithPositionKeywordUsesSendMessageIntent() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "위치 메시지 보내줘")

        guard case .sendMessage(let targetName, let message, let isCurrentLocation) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "")
        XCTAssertEqual(message, "")
        XCTAssertTrue(isCurrentLocation)
    }

    func testMessageTreatsLocationKeywordAsCurrentLocationWhenSharing() {
        let parser = SmartParser(contacts: ["정만"])
        let intent = parser.parse(input: "정만에게 위치 카톡 보내기")

        guard case .sendMessage(let targetName, let message, let isCurrentLocation) = intent else {
            XCTFail("Expected sendMessage intent")
            return
        }

        XCTAssertEqual(targetName, "정만")
        XCTAssertEqual(message, "")
        XCTAssertTrue(isCurrentLocation)
    }

    func testContactSelectionContextTreatsLocationKeywordAsCurrentLocationWhenSharing() {
        let parser = SmartParser(contacts: ["정만", "정만수"])
        let context = parser.contactSelectionContext(input: "정만에게 위치 카톡 보내기")

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.isCurrentLocation, true)
        XCTAssertEqual(context?.message, "")
    }

    func testLocationShareShortcutSkipsWhenRecipientParticleExists() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "정만에게 위치 카톡 보내기")

        if case .sendMessage = intent {
            XCTFail("Should not shortcut to sendMessage when recipient particle exists")
        }
    }
    func testNavigationStripsCompoundKeywordKakaoNavi() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "카카오내비 강남역")

        guard case .navigation(let destination) = intent else {
            XCTFail("Expected navigation intent")
            return
        }

        XCTAssertEqual(destination, "강남역")
    }

    func testNavigationStripsSimpleKeyword() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "강남역 내비")

        guard case .navigation(let destination) = intent else {
            XCTFail("Expected navigation intent")
            return
        }

        XCTAssertEqual(destination, "강남역")
    }
}
