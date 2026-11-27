import Foundation
import BrightLightsSchema
import Testing

@Suite
struct StayPlanProjectionTests {
  private var ny: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    ny.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  @Test func projectionPlacesBookingsAndPinnedPlacesIntoDaysAndHidesMissingPlaces() {
    let householdID = UUID()
    let stay = Stay(id: UUID(), householdID: householdID, arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 12)))
    let cafe = Place(id: UUID(), householdID: householdID, name: "Cafe", latitude: 1, longitude: 2)
    let loose = Place(id: UUID(), householdID: householdID, name: "Loose", latitude: 1, longitude: 2)
    let listing = Listing(id: UUID(), sourceID: UUID(), stableKey: "show", title: "Booked show", startsAt: date(2027, 3, 11, 20), rung: .model, capturedBy: .mac)
    let item = StayPlanItem(id: UUID(), stayID: stay.id, placeID: cafe.id, day: date(2027, 3, 11), meal: .dinner)
    let noDay = StayPlanItem(id: UUID(), stayID: stay.id, placeID: loose.id)
    let missing = StayPlanItem(id: UUID(), stayID: stay.id, placeID: UUID())
    let result = StayPlanProjection(
      stay: stay, stays: [stay], places: [cafe, loose], planItems: [item, noDay, missing], visits: [],
      listings: [listing], sources: [], reactions: [Reaction(id: UUID(), listingID: listing.id, kind: .booked)],
      now: date(2027, 3, 10), calendar: ny
    )
    #expect(result.days.count == 3)
    #expect(result.days[1].places.map(\.place.id) == [cafe.id])
    #expect(result.days[1].bookings.map(\.id) == [listing.id])
    #expect(result.thisStay.map(\.place.id) == [loose.id])
  }

  @Test func oldOutOfStayDayDisplaysUnderThisStayAndMoveOffersOnlyUnvisitedPlaces() {
    let householdID = UUID()
    let old = Stay(id: UUID(), householdID: householdID, arrivesOn: date(2027, 3, 1), departure: .booked(date(2027, 3, 3)))
    let next = Stay(id: UUID(), householdID: householdID, arrivesOn: date(2027, 3, 12), departure: .booked(date(2027, 3, 14)))
    let unvisited = Place(id: UUID(), householdID: householdID, name: "Unvisited", latitude: 1, longitude: 2)
    let visited = Place(id: UUID(), householdID: householdID, name: "Visited", latitude: 1, longitude: 2)
    let items = [
      StayPlanItem(id: UUID(), stayID: old.id, placeID: unvisited.id, day: date(2027, 3, 5)),
      StayPlanItem(id: UUID(), stayID: old.id, placeID: visited.id)
    ]
    let result = StayPlanProjection(
      stay: old, stays: [old, next], places: [unvisited, visited], planItems: items,
      visits: [PlaceVisit(id: UUID(), placeID: visited.id, day: date(2027, 3, 3, 18))],
      listings: [], sources: [], reactions: [], now: date(2027, 3, 10), calendar: ny
    )
    #expect(result.isEnded)
    #expect(result.nextStay?.id == next.id)
    #expect(Set(result.thisStay.map(\.place.id)) == Set([unvisited.id, visited.id]))
    #expect(result.didntGetTo.map(\.place.id) == [unvisited.id])
    #expect(result.didntGetTo.first?.day == nil)
  }

  @Test func seasonalOffersIncludeOnlyUnpinnedToTryPlacesInSeasonDuringStay() {
    let householdID = UUID()
    let stay = Stay(id: UUID(), householdID: householdID, arrivesOn: date(2027, 3, 10), departure: .booked(date(2027, 3, 12)))
    let inSeason = Place(
      id: UUID(), householdID: householdID, name: "Pop-up", latitude: 1, longitude: 2,
      when: .once(from: date(2027, 3, 11), to: date(2027, 3, 20))
    )
    let always = Place(id: UUID(), householdID: householdID, name: "Always", latitude: 1, longitude: 2)
    let outOfSeason = Place(
      id: UUID(), householdID: householdID, name: "Later", latitude: 1, longitude: 2,
      when: .once(from: date(2027, 4, 1), to: date(2027, 4, 20))
    )
    var tried = Place(id: UUID(), householdID: householdID, name: "Tried", latitude: 1, longitude: 2)
    tried.standing = .tried(.wouldReturn)
    let result = StayPlanProjection(
      stay: stay, stays: [stay], places: [inSeason, always, outOfSeason, tried], planItems: [], visits: [],
      listings: [], sources: [], reactions: [], now: date(2027, 3, 10), calendar: ny
    )
    #expect(result.onOnlyNow.map(\.place.id) == [inSeason.id])
    #expect(result.onOnlyNow.first?.endsOn == date(2027, 3, 20))
  }
}
