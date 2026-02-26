import XCTest
@testable import AnyQuick

final class KoreanScheduleParserTests: XCTestCase {
    private var calendar: Calendar!
    private var parser: KoreanScheduleParser!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        parser = KoreanScheduleParser(calendar: calendar)
    }

    func testParsesRelativeDayWithTime() {
        let result = parser.parse("내일 오후 3시에 회의", baseDate: baseNow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "회의")
        XCTAssertEqual(result?.allDay, false)
        assertDate(result?.start, year: 2026, month: 2, day: 18, hour: 15, minute: 0)
    }

    func testParsesWeekModifierWeekdayMinuteAndLocation() {
        let result = parser.parse("다음주 화요일 오후 3시 반에 강남에서 팀 미팅", baseDate: baseNow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "팀 미팅")
        XCTAssertEqual(result?.location, "강남")
        assertDate(result?.start, year: 2026, month: 2, day: 24, hour: 15, minute: 30)
    }

    func testCreatesAllDayEventWhenTimeOmitted() {
        let result = parser.parse("오늘 휴가", baseDate: baseNow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allDay, true)
        assertDate(result?.start, year: 2026, month: 2, day: 17, hour: 0, minute: 0)
        assertDate(result?.end, year: 2026, month: 2, day: 18, hour: 0, minute: 0)
    }

    func testMovesWeekdayOnlyExpressionToNextWeekWhenPassed() {
        let now = makeDate(year: 2026, month: 2, day: 17, hour: 16, minute: 0)
        let result = parser.parse("월요일 오후 3시에 회의", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 23, hour: 15, minute: 0)
    }

    func testFailsWhenSentenceDoesNotMatchPattern() {
        let result = parser.parse("회의 잡아줘", baseDate: baseNow)
        XCTAssertNil(result)
    }

    func testDoesNotCrashWhenAbsoluteDateTokenAbsent() {
        let now = makeDate(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let result = parser.parse("화요일 오후 3시에 회의", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 17, hour: 15, minute: 0)
    }

    func testKeeps12PMAsNoon() {
        let result = parser.parse("오늘 오후 12시에 점심", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 17, hour: 12, minute: 0)
    }

    func testConverts12AMToMidnight() {
        let result = parser.parse("내일 오전 12시에 알람", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 18, hour: 0, minute: 0)
    }

    func testFailsWhenAMPMCombinedWith24HourClock() {
        let result = parser.parse("오늘 오후 14:30에 회의", baseDate: baseNow)
        XCTAssertNil(result)
    }

    func testParses24HourTimeWithoutAMPM() {
        let result = parser.parse("오늘 14:30에 회의", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 17, hour: 14, minute: 30)
    }

    func testParsesExplicitYearMonthDay() {
        let result = parser.parse("2026년 3월 2일 오후 1시에 분기 리뷰", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 3, day: 2, hour: 13, minute: 0)
    }

    func testParsesNextYearExpression() {
        let result = parser.parse("내년 1월 2일 오전 9시에 시무식", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2027, month: 1, day: 2, hour: 9, minute: 0)
    }

    func testParsesNextMonthDayExpressionWithoutTime() {
        let result = parser.parse("다음달 3일 월간 결산", baseDate: baseNow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allDay, true)
        assertDate(result?.start, year: 2026, month: 3, day: 3, hour: 0, minute: 0)
    }

    func testKeepsExplicitTodayWhenTimeAlreadyPassed() {
        let now = makeDate(year: 2026, month: 2, day: 17, hour: 16, minute: 0)
        let result = parser.parse("오늘 오후 3시에 회의", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 17, hour: 15, minute: 0)
    }

    func testHandlesNextMonthDayFromMonthEnd() {
        let now = makeDate(year: 2026, month: 1, day: 31, hour: 9, minute: 0)
        let result = parser.parse("다음달 15일 오후 3시에 점검", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 15, hour: 15, minute: 0)
    }

    func testResolvesThisWeekSundayWhenTodayIsSunday() {
        let now = makeDate(year: 2026, month: 2, day: 22, hour: 9, minute: 0)
        let result = parser.parse("이번주 일요일 오후 3시에 회의", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 22, hour: 15, minute: 0)
    }

    func testTreatsNight12AsMidnightOfNextDay() {
        let result = parser.parse("오늘 밤 12시에 알람", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 18, hour: 0, minute: 0)
    }

    func testUsesNearestLocationWhenMultipleEse() {
        let result = parser.parse("내일 오후 3시에 강남역에서 만나는 부산에서 온 친구와 미팅", baseDate: baseNow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.location, "강남역")
    }

    func testRollsMonthDayWithoutYearToNextYearWhenPast() {
        let now = makeDate(year: 2026, month: 12, day: 31, hour: 10, minute: 0)
        let result = parser.parse("1월 1일 오후 3시에 새해 회의", baseDate: now)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2027, month: 1, day: 1, hour: 15, minute: 0)
    }

    func testFailsOnInvalidMonthDay() {
        let result = parser.parse("2월 31일 오후 3시에 테스트", baseDate: baseNow)
        XCTAssertNil(result)
    }

    func testFailsOnInvalid24HourTime() {
        let result = parser.parse("오늘 24:30에 테스트", baseDate: baseNow)
        XCTAssertNil(result)
    }

    func testFailsOnInvalidAMPMHour() {
        let result = parser.parse("오늘 오후 13시에 테스트", baseDate: baseNow)
        XCTAssertNil(result)
    }

    func testParsesDayModifierMore() {
        let result = parser.parse("모레 오전 9시에 출근", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 19, hour: 9, minute: 0)
    }

    func testParsesWeekAliasDamju() {
        let result = parser.parse("담주 화요일 오후 3시에 회의", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 2, day: 24, hour: 15, minute: 0)
    }

    func testParsesWeekAliasDadamju() {
        let result = parser.parse("다담주 화요일 오후 3시에 회의", baseDate: baseNow)
        XCTAssertNotNil(result)
        assertDate(result?.start, year: 2026, month: 3, day: 3, hour: 15, minute: 0)
    }

    func testIncludesSourceField() {
        let input = "내일 오후 3시에 회의"
        let result = parser.parse(input, baseDate: baseNow)
        XCTAssertEqual(result?.source, input)
    }

    func testParseResultReturnsErrorForEmptyInput() {
        let result = parser.parseResult("   ", baseDate: baseNow)
        switch result {
        case .success:
            XCTFail("Expected failure for empty input")
        case .failure(let error):
            XCTAssertFalse(error.message.isEmpty)
        }
    }
}

private extension KoreanScheduleParserTests {
    var baseNow: Date {
        makeDate(year: 2026, month: 2, day: 17, hour: 9, minute: 0)
    }

    func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    func assertDate(_ date: Date?, year: Int, month: Int, day: Int, hour: Int, minute: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let date else {
            XCTFail("Expected date, got nil", file: file, line: line)
            return
        }
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, year, file: file, line: line)
        XCTAssertEqual(comps.month, month, file: file, line: line)
        XCTAssertEqual(comps.day, day, file: file, line: line)
        XCTAssertEqual(comps.hour, hour, file: file, line: line)
        XCTAssertEqual(comps.minute, minute, file: file, line: line)
    }
}
