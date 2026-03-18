import XCTest
@testable import Pasture

final class ModelEnvironmentTests: XCTestCase {
    func testTimeOfDayBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 5), calendar: calendar), .night)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 6), calendar: calendar), .morning)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 11), calendar: calendar), .morning)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 12), calendar: calendar), .afternoon)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 17), calendar: calendar), .afternoon)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 18), calendar: calendar), .evening)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 20), calendar: calendar), .evening)
        XCTAssertEqual(TimeOfDay.from(date: makeDate(hour: 21), calendar: calendar), .night)
    }

    func testModelComplexityParsing() {
        XCTAssertEqual(ModelComplexity.from(modelName: "phi-3-mini"), .small)
        XCTAssertEqual(ModelComplexity.from(modelName: "llama3:3b"), .small)
        XCTAssertEqual(ModelComplexity.from(modelName: "mistral:7b"), .medium)
        XCTAssertEqual(ModelComplexity.from(modelName: "llama3:8b"), .medium)
        XCTAssertEqual(ModelComplexity.from(modelName: "qwen:13b"), .medium)
        XCTAssertEqual(ModelComplexity.from(modelName: "deepseek-r1:70b"), .large)
        XCTAssertEqual(ModelComplexity.from(modelName: "r1"), .large)
        XCTAssertEqual(ModelComplexity.from(modelName: "unknown-model"), .medium)
        XCTAssertEqual(ModelComplexity.from(modelName: nil), .medium)
    }

    func testPaletteLayerCountMatchesComplexity() {
        XCTAssertEqual(ModelEnvironment(timeOfDay: .morning, complexity: .small, isLateNight: false).palette.layerCount, 2)
        XCTAssertEqual(ModelEnvironment(timeOfDay: .morning, complexity: .medium, isLateNight: false).palette.layerCount, 3)
        XCTAssertEqual(ModelEnvironment(timeOfDay: .morning, complexity: .large, isLateNight: false).palette.layerCount, 4)
    }

    func testScreenThemeDefaultsAndLiveTheme() {
        let onboarding = ModelEnvironment.onboardingDefault
        XCTAssertEqual(onboarding.timeOfDay, .morning)
        XCTAssertEqual(onboarding.complexity, .medium)

        let morningDate = makeDate(hour: 9)
        let chat = ModelEnvironment.chat(for: "llama3:3b", at: morningDate)
        XCTAssertEqual(chat.timeOfDay, .morning)
        XCTAssertEqual(chat.complexity, .small)
        XCTAssertFalse(chat.isLateNight)

        let lateNight = ModelEnvironment.chat(for: "qwen:14b", at: makeDate(hour: 2))
        XCTAssertEqual(lateNight.timeOfDay, .night)
        XCTAssertTrue(lateNight.isLateNight)
    }

    private func makeDate(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = 0
        components.second = 0

        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
