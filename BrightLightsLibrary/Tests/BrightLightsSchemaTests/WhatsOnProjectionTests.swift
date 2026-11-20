import Foundation
import BrightLightsSchema
import Testing

@Suite
struct WhatsOnProjectionTests {
  private var ny: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    ny.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func listing(_ title: String, start: Date, close: Date? = nil, sourceID: UUID = UUID(), status: ListingStatus = .listed, onSale: Date? = nil) -> Listing {
    Listing(id: UUID(), sourceID: sourceID, stableKey: title, title: title, onSaleAt: onSale, startsAt: start, closesAt: close, status: status, rung: .model, capturedBy: .mac)
  }

  @Test func bookedTentativeAndOpenStayBoundaries() {
    let today = date(2027, 3, 10, 12)
    let booked = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 12)))
    let tentative = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .tentative(date(2027, 3, 12)))
    let open = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .open)
    let bookedResult = WhatsOnProjection(listings: [], sources: [], stays: [booked], reactions: [], now: today, calendar: .current)
    let openResult = WhatsOnProjection(listings: [], sources: [], stays: [open], reactions: [], now: today, calendar: .current)
    #expect(bookedResult.whileHere?.stay?.departureKind == .booked)
    #expect(openResult.whileHere?.stay?.departureKind == .open)
    #expect(StayRules.departureDate(tentative.departure, arrival: tentative.arrivesOn, calendar: ny) == date(2027, 3, 12))
  }

  @Test func earliestOverlappingCurrentStayWinsAndNextStayIsSelected() {
    let now = date(2027, 3, 11, 12)
    let later = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 12)))
    let earlier = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 9), departure: .booked(date(2027, 3, 13)))
    let next = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 20), departure: .booked(date(2027, 3, 23)))
    let result = WhatsOnProjection(listings: [], sources: [], stays: [later, next, earlier], reactions: [], now: now, calendar: .current)
    #expect(result.currentStay?.id == earlier.id)
    #expect(result.nextStay?.id == next.id)
  }

  @Test func newYorkGroupingSurvivesLosAngelesCalendarAndLateShowBelongsToNextDay() {
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let now = date(2027, 3, 13, 20)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 13), departure: .booked(date(2027, 3, 15)))
    let late = listing("Late set", start: date(2027, 3, 14, 0))
    let result = WhatsOnProjection(listings: [late], sources: [], stays: [stay], reactions: [], now: now, calendar: losAngeles)
    #expect(result.whileHere?.days.first?.date == date(2027, 3, 14))
    #expect(result.whileHere?.days.first?.items.first?.listing.id == late.id)
  }

  @Test func springDstWeekUsesCalendarDays() {
    let arrival = date(2027, 3, 12)
    let openDeparture = StayRules.departureDate(.open, arrival: arrival, calendar: ny)
    #expect(openDeparture == date(2027, 3, 19))
  }

  @Test func performanceRemainsVisibleUntilTwoHoursAfterStart() {
    let start = date(2027, 3, 10, 20)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 11)))
    let item = listing("Show", start: start)
    let before = WhatsOnProjection(listings: [item], sources: [], stays: [stay], reactions: [], now: date(2027, 3, 10, 21) + 59 * 60, calendar: ny)
    let exact = WhatsOnProjection(listings: [item], sources: [], stays: [stay], reactions: [], now: date(2027, 3, 10, 22), calendar: ny)
    let after = WhatsOnProjection(listings: [item], sources: [], stays: [stay], reactions: [], now: date(2027, 3, 10, 21) + 61 * 60, calendar: ny)
    #expect(before.whileHere?.days.flatMap(\.items).contains(where: { $0.id == item.id }) == true)
    #expect(exact.whileHere?.days.flatMap(\.items).contains(where: { $0.id == item.id }) == true)
    #expect(after.whileHere?.days.flatMap(\.items).contains(where: { $0.id == item.id }) == false)
  }

  @Test func runAppearsOnceAndMissingCancelledRequireReaction() {
    let now = date(2027, 3, 10, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .tentative(date(2027, 3, 12)))
    let run = listing("Run", start: date(2027, 3, 1), close: date(2027, 3, 20))
    let cancelled = listing("Cancelled", start: date(2027, 3, 11), status: .cancelled)
    let missing = listing("Missing", start: date(2027, 3, 11), status: .missing)
    let missingWithReaction = listing("Missing with reaction", start: date(2027, 3, 11), status: .missing)
    let reactions = [
      Reaction(id: UUID(), listingID: cancelled.id, kind: .booked),
      Reaction(id: UUID(), listingID: missingWithReaction.id, kind: .interested)
    ]
    let result = WhatsOnProjection(listings: [run, cancelled, missing, missingWithReaction], sources: [], stays: [stay], reactions: reactions, now: now, calendar: ny)
    #expect(result.whileHere?.running.map(\.id) == [run.id])
    let visibleItems = result.whileHere?.days.flatMap(\.items) ?? []
    #expect(Set(visibleItems.map(\.id)) == Set([cancelled.id, missingWithReaction.id]))
    #expect(Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0.badge) }) == [cancelled.id: "Cancelled", missingWithReaction.id: "No longer listed"])
    #expect(result.whileHere?.running.count == 1)
  }

  @Test func futureRunAppearsInItsStayAndRunningGroupBeforeOpening() {
    let now = date(2027, 3, 10, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 12), departure: .booked(date(2027, 3, 15)))
    let run = listing("Future run", start: date(2027, 3, 12, 19), close: date(2027, 3, 25))
    let result = WhatsOnProjection(listings: [run], sources: [], stays: [stay], reactions: [], now: now, calendar: ny)
    #expect(result.comingUp.first?.running.map(\.id) == [run.id])
    #expect(result.showEverythingByWeek.flatMap(\.days).flatMap(\.items).map(\.id) == [run.id])
  }

  @Test func passesAreHiddenAndLatestDuplicateReactionWins() {
    let now = date(2027, 3, 10, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 13)))
    let passed = listing("Passed", start: date(2027, 3, 11))
    let duplicate = listing("Duplicate", start: date(2027, 3, 11))
    let reactions = [
      Reaction(id: UUID(), listingID: passed.id, kind: .interested, updatedAt: date(2027, 3, 1)),
      Reaction(id: UUID(), listingID: passed.id, kind: .pass, updatedAt: date(2027, 3, 2)),
      Reaction(id: UUID(), listingID: duplicate.id, kind: .interested, updatedAt: date(2027, 3, 1)),
      Reaction(id: UUID(), listingID: duplicate.id, kind: .booked, updatedAt: date(2027, 3, 2))
    ]
    let result = WhatsOnProjection(listings: [passed, duplicate], sources: [], stays: [stay], reactions: reactions, now: now, calendar: ny)
    #expect(result.passedCount == 1)
    #expect(result.whileHere?.days.flatMap(\.items).map(\.id) == [duplicate.id])
    #expect(result.whileHere?.days.flatMap(\.items).first?.reaction?.kind == .booked)
  }

  @Test func extraDayOnlyForTentativeOrOpenDeparture() {
    let now = date(2027, 3, 10, 12)
    let tentative = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .tentative(date(2027, 3, 12)))
    let booked = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 12)))
    let extra = listing("Extra", start: date(2027, 3, 13, 19))
    let tentativeResult = WhatsOnProjection(listings: [extra], sources: [], stays: [tentative], reactions: [], now: now, calendar: ny)
    let bookedResult = WhatsOnProjection(listings: [extra], sources: [], stays: [booked], reactions: [], now: now, calendar: ny)
    #expect(tentativeResult.whileHere?.extraDay?.items.first?.id == extra.id)
    #expect(tentativeResult.whileHere?.days.contains(where: { $0.items.contains(where: { $0.id == extra.id }) }) == false)
    #expect(bookedResult.whileHere?.days.isEmpty == true)
    #expect(bookedResult.whileHere?.extraDay == nil)
  }

  @Test func showEverythingGroupsOutOfStayListingsByWeek() {
    let now = date(2027, 3, 1, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 8), departure: .booked(date(2027, 3, 10)))
    let inside = listing("Inside", start: date(2027, 3, 9, 20))
    let outside = listing("Outside", start: date(2027, 3, 18, 20))
    let result = WhatsOnProjection(listings: [inside, outside], sources: [], stays: [stay], reactions: [], now: now, calendar: ny)
    #expect(result.comingUp.flatMap(\.days).flatMap(\.items).map(\.id) == [inside.id])
    #expect(result.showEverythingByWeek.flatMap(\.days).flatMap(\.items).map(\.id) == [inside.id, outside.id])
  }

  @Test func comingUpIncludesPerformanceOnDepartureDay() {
    let now = date(2027, 3, 1, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 8), departure: .booked(date(2027, 3, 10)))
    let departureNight = listing("Departure night", start: date(2027, 3, 10, 20))
    let result = WhatsOnProjection(listings: [departureNight], sources: [], stays: [stay], reactions: [], now: now, calendar: ny)
    #expect(result.comingUp.first?.days.flatMap(\.items).map(\.id) == [departureNight.id])
  }

  @Test func closingDeadlinesCountFutureStaysAndOnSaleWindowIsFourteenDays() {
    let now = date(2027, 3, 1, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 8), departure: .booked(date(2027, 3, 10)))
    let closing = listing("Closing", start: date(2027, 2, 1), close: date(2027, 3, 20))
    let saleSoon = listing("Sale", start: date(2027, 4, 1), onSale: date(2027, 3, 14))
    let saleLate = listing("Late sale", start: date(2027, 4, 2), onSale: date(2027, 3, 16))
    let result = WhatsOnProjection(listings: [closing, saleSoon, saleLate], sources: [], stays: [stay], reactions: [], now: now, calendar: ny)
    #expect(result.deadlines.closing.first?.staysBeforeClose == 1)
    #expect(result.deadlines.onSale.map(\.id) == [saleSoon.id])
  }

  @Test func currentStayComingUpStartsTomorrowAndNoStayFallsBackToWeeks() {
    let now = date(2027, 3, 10, 12)
    let current = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 8), departure: .tentative(date(2027, 3, 12)))
    let tonight = listing("Tonight", start: date(2027, 3, 10, 20))
    let tomorrow = listing("Tomorrow", start: date(2027, 3, 11, 20))
    let currentResult = WhatsOnProjection(listings: [tonight, tomorrow], sources: [], stays: [current], reactions: [], now: now, calendar: ny)
    #expect(currentResult.comingUp.first?.days.flatMap(\.items).map(\.id) == [tomorrow.id])

    let noStay = WhatsOnProjection(listings: [tomorrow], sources: [], stays: [], reactions: [], now: now, calendar: ny)
    #expect(noStay.comingUp.count == 1)
    #expect(noStay.comingUp.first?.note == "Add your next stay to narrow this")
  }

  @Test func closingCountCoversZeroOneAndTwoFutureStays() {
    let now = date(2027, 3, 1, 12)
    let stays = [
      Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 8), departure: .booked(date(2027, 3, 9))),
      Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 15), departure: .booked(date(2027, 3, 16)))
    ]
    let zero = listing("Zero", start: date(2027, 2, 1), close: date(2027, 3, 5))
    let one = listing("One", start: date(2027, 2, 1), close: date(2027, 3, 10))
    let two = listing("Two", start: date(2027, 2, 1), close: date(2027, 3, 20))
    let result = WhatsOnProjection(listings: [zero, one, two], sources: [], stays: stays, reactions: [], now: now, calendar: ny)
    #expect(result.deadlines.closing.map(\.staysBeforeClose) == [0, 1, 2])
  }

  @Test func deadlinesHideCancelledAndMissingListingsWithoutAReaction() {
    let now = date(2027, 3, 1, 12)
    let cancelled = listing("Cancelled", start: date(2027, 3, 20), close: date(2027, 3, 25), status: .cancelled, onSale: date(2027, 3, 5))
    let missing = listing("Missing", start: date(2027, 3, 20), close: date(2027, 3, 25), status: .missing, onSale: date(2027, 3, 6))
    let result = WhatsOnProjection(listings: [cancelled, missing], sources: [], stays: [], reactions: [], now: now, calendar: ny)
    #expect(result.deadlines.onSale.isEmpty)
    #expect(result.deadlines.closing.isEmpty)
  }

  @Test func filterOffersPickedInterestedBookedAndEverything() {
    let now = date(2027, 3, 10, 12)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 13)))
    let interested = listing("Interested", start: date(2027, 3, 11))
    let booked = listing("Booked", start: date(2027, 3, 12))
    let kept = listing("Kept", start: date(2027, 3, 13))
    let untouched = listing("Untouched", start: date(2027, 3, 13))
    let cleared = listing("Cleared", start: date(2027, 3, 15))
    let reactions = [
      Reaction(id: UUID(), listingID: interested.id, kind: .interested),
      Reaction(id: UUID(), listingID: booked.id, kind: .booked),
      Reaction(id: UUID(), listingID: kept.id, kind: .kept),
      Reaction(id: UUID(), listingID: cleared.id, kind: .cleared)
    ]
    let result = WhatsOnProjection(listings: [interested, booked, kept, untouched, cleared], sources: [], stays: [stay], reactions: reactions, now: now, calendar: ny)
    let all = result.comingUp.flatMap(\.days).flatMap(\.items)
    #expect(result.filtered(all, by: .picked).count == 3)
    #expect(result.filtered(all, by: .interestedAndBooked).count == 2)
    #expect(result.filtered(all, by: .booked).map(\.id) == [booked.id])
    #expect(result.filtered(all, by: .everything).count == 4)
    #expect(!all.contains { $0.id == cleared.id })
  }

  @Test func stayValidationRejectsEarlierDepartureAndNamesOverlap() throws {
    let arrival = date(2027, 3, 10)
    let other = Stay(id: UUID(), householdID: UUID(), arrivesOn: date(2027, 3, 12), departure: .booked(date(2027, 3, 14)))
    #expect(throws: StayValidationError.departureBeforeArrival) {
      try StayRules.validate(arrival: arrival, departure: .booked(date(2027, 3, 9)), against: [], calendar: ny)
    }
    #expect(throws: StayValidationError.overlaps(other.id)) {
      try StayRules.validate(arrival: arrival, departure: .tentative(date(2027, 3, 13)), against: [other], calendar: ny)
    }
    #expect(StayRules.normalized(date(2027, 3, 10, 23), calendar: .current) == date(2027, 3, 10))
  }

  @Test func pickerValuesUseTheNewYorkCalendarOnPacificAndLondonDevices() {
    var pacific = Calendar(identifier: .gregorian)
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    var london = Calendar(identifier: .gregorian)
    london.timeZone = TimeZone(identifier: "Europe/London")!
    let pacificDevicePickerValue = date(2027, 1, 10, 23)
    let londonDevicePickerValue = ny.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 0, minute: 30))!
    let expected = date(2027, 1, 10)
    #expect(StayRules.normalized(pacificDevicePickerValue, calendar: pacific) == expected)
    #expect(StayRules.normalized(londonDevicePickerValue, calendar: london) == expected)
  }
}
