import BrightLightsSchema
import Dependencies
import SQLiteData
import Sharing
import SwiftUI

struct StayPlanView: View {
  let initialStay: Stay
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays: [Stay]
  @FetchAll private var places: [Place]
  @FetchAll private var planItems: [StayPlanItem]
  @FetchAll private var visits: [PlaceVisit]
  @FetchAll(Listing.canonical) private var listings: [Listing]
  @FetchAll(Source.active.order(by: \.name)) private var sources: [Source]
  @FetchAll private var reactions: [Reaction]
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.date.now) private var dateNow
  @Shared(.currentPersonID) private var currentPersonIDString
  @State private var editingPin: StayPlanPlace?
  @State private var visitingPlace: StayPlanPlace?
  @State private var showingMoveConfirmation = false
  @State private var errorMessage: String?

  init(stay: Stay) { initialStay = stay }

  private var stay: Stay { stays.first(where: { $0.id == initialStay.id }) ?? initialStay }
  private func makeProjection() -> StayPlanProjection {
    StayPlanProjection(
      stay: stay, stays: stays, places: places, planItems: planItems, visits: visits,
      listings: listings, sources: sources, reactions: reactions, now: dateNow, calendar: .newYork
    )
  }

  var body: some View {
    let projection = makeProjection()
    List {
      ForEach(projection.days) { day in
        Section(dayTitle(day.date)) {
          ForEach(day.bookings) { item in
            NavigationLink { ListingDetailView(item: item) } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(item.listing.title).font(.headline)
                Text("\(ListingDisplay.newYorkDateTime(item.listing.startsAt)) · \(item.sourceName)")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }
          ForEach(day.places) { planned in placeRow(planned) }
          if day.bookings.isEmpty && day.places.isEmpty {
            Text("Nothing planned").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
      Section("This stay") {
        if projection.thisStay.isEmpty {
          Text("No places pinned yet").foregroundStyle(.secondary)
        } else {
          ForEach(projection.thisStay) { planned in placeRow(planned) }
        }
      }
      if !projection.onOnlyNow.isEmpty {
        Section("On only now") {
          ForEach(projection.onOnlyNow) { offer in
            HStack(spacing: 12) {
              NavigationLink { PlaceDetailView(place: offer.place) } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(offer.place.name)
                  Text(offer.endsOn.map { "Ends \(nyDate($0))" } ?? "In season")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Button("Pin") { pin(offer.place, day: nil, meal: nil) }
                .buttonStyle(.bordered)
            }
          }
        }
      }
      if projection.isEnded, !projection.didntGetTo.isEmpty {
        Section("Didn't get to") {
          ForEach(projection.didntGetTo) { planned in
            NavigationLink { PlaceDetailView(place: planned.place) } label: {
              Text(planned.place.name)
            }
          }
          if projection.nextStay != nil {
            Button("Move them to next stay…", systemImage: "arrow.right") { showingMoveConfirmation = true }
          } else {
            Text("Add another stay to move these places forward.").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Plan · \(stayTitle(stay))")
    .sheet(item: $editingPin) { planned in
      NavigationStack {
        AddPlaceToStayView(place: planned.place, editing: stay, day: planned.item.day, meal: planned.item.meal)
      }
    }
    .sheet(item: $visitingPlace) { planned in
      NavigationStack {
        LogPlaceVisitView(
          place: planned.place, initialDay: planned.day ?? stay.clampedDay(dateNow, calendar: .newYork),
          initialMeal: planned.item.meal
        ) {
          logVisit(planned.place, day: $0, meal: $1, note: $2, verdict: $3)
        }
      }
    }
    .confirmationDialog(
      "Move these places to \(projection.nextStay.map(stayTitle) ?? "the next stay")?",
      isPresented: $showingMoveConfirmation,
      titleVisibility: .visible
    ) {
      Button("Move \(projection.didntGetTo.count) places", systemImage: "arrow.right") { moveNotGotTo() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The original plan stays as history. Places already visited during this stay won't move.")
    }
    .alert("Stay plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  @ViewBuilder
  private func placeRow(_ planned: StayPlanPlace) -> some View {
    HStack(spacing: 10) {
      NavigationLink { PlaceDetailView(place: planned.place) } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text(planned.place.name)
          if let meal = planned.item.meal {
            Text(meal.title).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
      Button("Went") { visitingPlace = planned }
        .buttonStyle(.bordered)
        .accessibilityLabel("Log visit to \(planned.place.name)")
    }
    .contextMenu {
      Button("Change day or meal", systemImage: "pencil") { editingPin = planned }
      Button("Remove from stay", systemImage: "pin.slash", role: .destructive) { remove(planned) }
    }
  }

  private func pin(_ place: Place, day: Date?, meal: Meal?) {
    let stayID = stay.id
    let placeID = place.id
    let authorID = UUID(uuidString: currentPersonIDString)
    let now = dateNow
    Task {
      do {
        try await database.write { db in
          guard try StayPlanOperations.pin(
            placeID: placeID, to: stayID, day: day, meal: meal, authorID: authorID, now: now, in: db
          ) != nil else { throw StayPlanError.placeOrStayUnavailable }
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  private func remove(_ planned: StayPlanPlace) {
    let stayID = stay.id
    let placeID = planned.place.id
    Task {
      do { try await database.write { db in try StayPlanOperations.remove(placeID: placeID, from: stayID, in: db) } }
      catch { errorMessage = error.localizedDescription }
    }
  }

  private func logVisit(_ place: Place, day: Date, meal: Meal?, note: String, verdict: Verdict?) {
    let visit = PlaceVisit(
      id: UUID(), placeID: place.id, day: day, meal: meal, note: note.isEmpty ? nil : note,
      authorID: UUID(uuidString: currentPersonIDString), createdAt: dateNow
    )
    Task {
      do { try await database.write { db in try PlaceOperations.logVisit(visit, verdict: verdict, in: db) } }
      catch { errorMessage = error.localizedDescription }
    }
  }

  private func moveNotGotTo() {
    let stayID = stay.id
    let visitRows = visits
    let authorID = UUID(uuidString: currentPersonIDString)
    let now = dateNow
    Task {
      do {
        try await database.write { db in
          _ = try StayPlanOperations.moveNotGotToNextStay(from: stayID, visits: visitRows, authorID: authorID, now: now, in: db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  private func dayTitle(_ date: Date) -> String {
    if Calendar.newYork.isDateInToday(date) { return "Today · \(nyWeekdayDate(date))" }
    return nyWeekdayDate(date)
  }
}

struct AddPlaceToStayView: View {
  let place: Place
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays: [Stay]
  @Environment(\.dismiss) private var dismiss
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.date.now) private var dateNow
  @Shared(.currentPersonID) private var currentPersonIDString
  /// The stay the pin is in when editing an existing pin; nil when adding a new one.
  private let originalStayID: UUID?
  @State private var selectedStayID: UUID?
  @State private var includesDay: Bool
  @State private var day: Date
  @State private var meal: Meal?
  @State private var errorMessage: String?

  init(place: Place, editing stay: Stay? = nil, day: Date? = nil, meal: Meal? = nil) {
    self.place = place
    @Dependency(\.date.now) var dateNow
    originalStayID = stay?.id
    _selectedStayID = State(initialValue: stay?.id)
    _includesDay = State(initialValue: day != nil)
    _day = State(initialValue: day ?? dateNow)
    _meal = State(initialValue: meal)
  }

  private var selectedStay: Stay? { stays.first { $0.id == selectedStayID } }

  var body: some View {
    Form {
      if stays.isEmpty {
        ContentUnavailableView("No stays planned", systemImage: "house", description: Text("Add a stay before pinning a place."))
      } else {
        Picker("Stay", selection: $selectedStayID) {
          ForEach(stays) { stay in Text(stayTitle(stay)).tag(Optional(stay.id)) }
        }
        Toggle("Choose a day", isOn: $includesDay)
        if includesDay, let selectedStay {
          DatePicker(
            "Day", selection: $day, in: selectedStay.dayRange(calendar: .newYork), displayedComponents: .date
          )
        }
        Picker("Meal", selection: $meal) {
          Text("Any meal").tag(Meal?.none)
          ForEach(Meal.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
      }
    }
    .environment(\.calendar, .newYork)
    .environment(\.timeZone, Calendar.newYork.timeZone)
    .navigationTitle("Add to stay")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(selectedStay == nil)
      }
    }
    .alert("Couldn't pin place", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorMessage ?? "") }
    // Stays can arrive after the sheet opens (first load, or sync from the other device), so re-check each time.
    .onChange(of: stays.map(\.id), initial: true) {
      if selectedStay == nil {
        selectedStayID = (Self.defaultStay(in: stays, now: dateNow, calendar: .newYork) ?? stays.first)?.id
      }
      clampDayToSelectedStay()
    }
    .onChange(of: selectedStayID) { clampDayToSelectedStay() }
  }

  private func clampDayToSelectedStay() {
    guard let selectedStay else { return }
    let clamped = selectedStay.clampedDay(day, calendar: .newYork)
    if clamped != Calendar.newYork.startOfDay(for: day) { day = clamped }
  }

  private func save() {
    guard let selectedStay else { return }
    let authorID = UUID(uuidString: currentPersonIDString)
    let now = dateNow
    let selectedDay = includesDay ? selectedStay.clampedDay(day, calendar: .newYork) : nil
    let selectedStayID = selectedStay.id
    let originalStayID = originalStayID ?? selectedStayID
    let selectedMeal = meal
    let placeID = place.id
    Task {
      do {
        try await database.write { db in
          guard try StayPlanOperations.repin(
            placeID: placeID, from: originalStayID, to: selectedStayID, day: selectedDay, meal: selectedMeal,
            authorID: authorID, now: now, in: db
          ) != nil else { throw StayPlanError.placeOrStayUnavailable }
        }
        dismiss()
      } catch { errorMessage = error.localizedDescription }
    }
  }

  private static func defaultStay(in stays: [Stay], now: Date, calendar: Calendar) -> Stay? {
    WhatsOnProjection.currentStay(in: stays, now: now, calendar: calendar)
      ?? stays.first { calendar.startOfDay(for: $0.arrivesOn) >= calendar.startOfDay(for: now) }
  }
}

private enum StayPlanError: LocalizedError {
  case placeOrStayUnavailable
  var errorDescription: String? { "The place or stay is no longer available." }
}

private extension Calendar {
  static var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
}

private func stayTitle(_ stay: Stay) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = Calendar.newYork.timeZone
  formatter.dateFormat = "MMM d"
  let end = stay.departsOn.map(formatter.string(from:)) ?? "Open"
  return "\(formatter.string(from: stay.arrivesOn))–\(end)"
}

private func nyWeekdayDate(_ date: Date) -> String {
  date.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: Calendar.newYork.timeZone))
}

private func nyDate(_ date: Date) -> String {
  date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: Calendar.newYork.timeZone))
}
