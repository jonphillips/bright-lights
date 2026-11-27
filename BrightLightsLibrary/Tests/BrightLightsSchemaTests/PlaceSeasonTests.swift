import BrightLightsSchema
import Foundation
import Testing

@Suite struct PlaceSeasonTests {
  private var ny: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    ny.date(from: DateComponents(year: year, month: month, day: day))!
  }

  @Test func alwaysAndYearlySeasonEdges() {
    #expect(PlaceSeason.resolve(.always, today: date(2027, 3, 1)) == .always)
    let summer = PlaceWhen.yearly(from: MonthDay(month: 6, day: 1), to: MonthDay(month: 8, day: 31))
    #expect(PlaceSeason.resolve(summer, today: date(2027, 5, 31)) == .outOfSeason(nextOn: date(2027, 6, 1)))
    #expect(PlaceSeason.resolve(summer, today: date(2027, 6, 1)) == .inSeason(endsOn: date(2027, 8, 31)))
    #expect(PlaceSeason.resolve(summer, today: date(2027, 7, 15)) == .inSeason(endsOn: date(2027, 8, 31)))
    #expect(PlaceSeason.resolve(summer, today: date(2027, 8, 31)) == .inSeason(endsOn: date(2027, 8, 31)))
    #expect(PlaceSeason.resolve(summer, today: date(2027, 9, 1)) == .outOfSeason(nextOn: date(2028, 6, 1)))
  }

  @Test func yearlySeasonCrossesNewYearAndClampsLeapDay() {
    let winter = PlaceWhen.yearly(from: MonthDay(month: 11, day: 20), to: MonthDay(month: 1, day: 5))
    #expect(PlaceSeason.resolve(winter, today: date(2027, 12, 31)) == .inSeason(endsOn: date(2028, 1, 5)))
    #expect(PlaceSeason.resolve(winter, today: date(2028, 1, 1)) == .inSeason(endsOn: date(2028, 1, 5)))
    #expect(PlaceSeason.resolve(winter, today: date(2028, 1, 6)) == .outOfSeason(nextOn: date(2028, 11, 20)))
    let leap = PlaceWhen.yearly(from: MonthDay(month: 2, day: 29), to: MonthDay(month: 3, day: 10))
    #expect(PlaceSeason.resolve(leap, today: date(2027, 2, 27)) == .outOfSeason(nextOn: date(2027, 2, 28)))
  }

  @Test func onceSeasonBeforeDuringAndAfter() {
    let once = PlaceWhen.once(from: date(2027, 3, 3), to: date(2027, 3, 5))
    #expect(PlaceSeason.resolve(once, today: date(2027, 3, 2)) == .outOfSeason(nextOn: date(2027, 3, 3)))
    #expect(PlaceSeason.resolve(once, today: date(2027, 3, 3)) == .inSeason(endsOn: date(2027, 3, 5)))
    #expect(PlaceSeason.resolve(once, today: date(2027, 3, 4)) == .inSeason(endsOn: date(2027, 3, 5)))
    #expect(PlaceSeason.resolve(once, today: date(2027, 3, 5)) == .inSeason(endsOn: date(2027, 3, 5)))
    #expect(PlaceSeason.resolve(once, today: date(2027, 3, 6)) == .ended(on: date(2027, 3, 5)))
  }
}
