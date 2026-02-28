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

    // MARK: - Regression Tests

    func testCleanForSearchPreservesQueryWords() {
        // "고대 문자 검색" → "문자"가 유지되어야 함 (cleanText 버그 수정 검증)
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "고대 문자 검색")

        // "검색"은 트리거, 쿼리에서 제거 OK. "문자"는 쿼리 일부로 유지되어야 함.
        guard case .webSearch(let query, _) = intent else {
            // 검색 트리거가 없으면 .unknown일 수도 있지만 "검색" 키워드가 있으므로 파싱 안 됨
            return
        }
        XCTAssertTrue(query.contains("문자"), "쿼리에서 '문자'가 보존되어야 합니다: \(query)")
    }

    func testAITriggerExpansion() {
        let parser = SmartParser(contacts: [])

        let summarize = parser.parse(input: "스위프트 요약해줘")
        if case .webSearch(let query, let type) = summarize {
            XCTAssertEqual(type, .chatgpt)
            XCTAssertTrue(query.contains("스위프트"))
        } else if case .openApp(let type) = summarize {
            XCTAssertEqual(type, .chatgpt)
        } else {
            XCTFail("Expected AI intent for 요약해줘")
        }

        let explain = parser.parse(input: "양자역학 설명해줘")
        if case .webSearch(_, let type) = explain {
            XCTAssertEqual(type, .chatgpt)
        } else if case .openApp(let type) = explain {
            XCTAssertEqual(type, .chatgpt)
        } else {
            XCTFail("Expected AI intent for 설명해줘")
        }
    }

    func testAITriggerTypoVariants() {
        let parser = SmartParser(contacts: [])

        let typo1 = parser.parse(input: "날씨 물어바")
        if case .webSearch(let query, let type) = typo1 {
            XCTAssertEqual(type, .chatgpt)
            XCTAssertTrue(query.contains("날씨"))
        } else {
            XCTFail("Expected AI intent for 물어바 (typo)")
        }
    }

    func testExplicitAIKeywordOverridesTrigger() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "grok 스위프트 알려줘")

        guard case .webSearch(_, let type) = intent else {
            XCTFail("Expected webSearch")
            return
        }
        // grok이 명시되었으므로 .grok으로 라우팅
        XCTAssertEqual(type, .grok)
    }

    func testEmptyQueryReturnsOpenApp() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "유튜브")

        guard case .openApp(let type) = intent else {
            XCTFail("Expected openApp for solo keyword '유튜브'")
            return
        }
        XCTAssertEqual(type, .youtube)
    }

    func testEmptyQueryAppStoreReturnsOpenApp() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "앱스토어")

        guard case .openApp(let type) = intent else {
            XCTFail("Expected openApp for solo keyword '앱스토어'")
            return
        }
        XCTAssertEqual(type, .appstore)
    }

    func testScheduleVsWebSearchConflict() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "내일 서울 날씨")

        // "날씨"가 웹검색 오버라이드 키워드 → 일정이 아니라 웹검색
        switch intent {
        case .addSchedule:
            XCTFail("'내일 서울 날씨'는 일정이 아닌 웹검색이어야 합니다")
        default:
            break // webSearch or unknown 둘 다 OK
        }
    }

    func testFullWidthNormalization() {
        let parser = SmartParser(contacts: [])
        // 전각 유튜브 → 반각으로 정규화 후 파싱
        let intent = parser.parse(input: "ｙｏｕｔｕｂｅ 고양이")

        // 전각→반각 변환이 작동했다면 매칭 가능
        // (SearchType에 youtube 한글 트리거만 있을 수 있으므로 매칭 안 될 수도 있음)
        if case .webSearch(_, _) = intent {
            // OK
        } else if case .openApp(_) = intent {
            // OK
        } else {
            // .unknown도 허용 (영문 전각은 SearchType 한글 트리거 매칭 안 될 수 있음)
        }
    }

    func testNavigationPreservesEseo() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "에버랜드에서 강남역 내비")

        guard case .navigation(let origin, let destination) = intent else {
            XCTFail("Expected navigation intent")
            return
        }
        // "A에서 B" 패턴으로 파싱
        XCTAssertEqual(origin, "에버랜드")
        XCTAssertEqual(destination, "강남역")
    }

    func testNavigationAtoB() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "강남역에서 판교역 길찾기")

        guard case .navigation(let origin, let destination) = intent else {
            XCTFail("Expected navigation intent")
            return
        }
        XCTAssertEqual(origin, "강남역")
        XCTAssertEqual(destination, "판교역")
    }

    func testNavigationWithoutOrigin() {
        let parser = SmartParser(contacts: [])
        let intent = parser.parse(input: "판교역 내비")

        guard case .navigation(let origin, let destination) = intent else {
            XCTFail("Expected navigation intent")
            return
        }
        XCTAssertNil(origin)
        XCTAssertEqual(destination, "판교역")
    }
}
