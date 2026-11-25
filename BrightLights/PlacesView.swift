import BrightLightsPlaces
import BrightLightsSchema
import Dependencies
import MapPlacesKit
import SQLiteData
import Sharing
import SwiftUI

struct PlacesView: View {
  @FetchAll private var households: [Household]
  @FetchAll(Place.order(by: \.name)) private var places: [Place]
  @FetchAll(PlaceVisit.order(by: \.day)) private var visits: [PlaceVisit]
  @FetchAll(SyncMetadata.where { $0.recordType.eq("households") }) private var metadata: [SyncMetadata]
  @Dependency(\.defaultDatabase) private var database
  @State private var placeForDetail: Place?
  @State private var showingSearch = false
  @State private var showingNotForUs = false
  @State private var errorMessage: String?

  private var household: Household? {
    guard !households.isEmpty else { return nil }
    return Household.survivor(in: households) { Household.sharingState(of: $0, metadata: metadata) }
  }
  private var projection: PlaceCheckSheet {
    PlaceCheckSheet(
      places: places.filter { $0.householdID == household?.id }, visits: visits,
      showingNotForUs: showingNotForUs
    )
  }

  var body: some View {
    List {
      if household == nil {
        ContentUnavailableView("Places unavailable", systemImage: "mappin.and.ellipse")
      } else if projection.groups.isEmpty {
        ContentUnavailableView {
          Label("No places", systemImage: "mappin.and.ellipse")
        } description: {
          Text("Add a place from Apple Maps to start your check sheet.")
        } actions: {
          Button("Add place", systemImage: "plus") { showingSearch = true }
            .buttonStyle(.borderedProminent)
        }
      } else {
        ForEach(projection.groups) { group in
          Section(group.title) {
            ForEach(group.rows) { row in
              Button { placeForDetail = row.place } label: {
                PlaceCheckSheetRowView(row: row)
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
    .navigationTitle("Places")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button(showingNotForUs ? "Hide Not for us" : "Show Not for us", systemImage: "eye") {
            showingNotForUs.toggle()
          }
          Button("Add place", systemImage: "plus") { showingSearch = true }
            .disabled(household == nil)
        } label: { Label("Places", systemImage: "ellipsis.circle") }
      }
    }
    .sheet(isPresented: $showingSearch) {
      NavigationStack { AddPlaceView(householdID: household?.id) { place in placeForDetail = place } }
    }
    .sheet(item: $placeForDetail) { place in NavigationStack { PlaceDetailView(place: place) } }
    .alert("Places", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

}

private struct PlaceCheckSheetRowView: View {
  let row: PlaceCheckSheet.Row
  private var detailParts: [String] {
    var parts: [String] = []
    let meals = Meal.allCases.filter(row.place.meals.values.contains).map(\.title).joined(separator: ", ")
    if !meals.isEmpty { parts.append(meals) }
    if case .tried = row.place.standing, let date = row.lastVisit {
      parts.append("Last visit \(date.formatted(Date.FormatStyle(timeZone: Calendar.newYork.timeZone).month(.abbreviated).day()))")
    }
    return parts
  }
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: row.place.kind.symbol).foregroundStyle(.secondary).frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.place.name).font(.headline)
        if !detailParts.isEmpty { Text(detailParts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
      }
      Spacer()
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.contentShape(.rect)
  }
}

private struct AddPlaceView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model = MapPlaceSearchModel(regions: [
    MapPlaceRegion(centerLatitude: 40.73, centerLongitude: -73.96, latitudeDelta: 0.35, longitudeDelta: 0.35)
  ], biased: true)
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.uuid) private var uuid
  @Dependency(\.date.now) private var dateNow
  let householdID: UUID?
  let onAdd: (Place) -> Void
  @State private var errorMessage: String?
  @State private var isResolving = false

  var body: some View {
    @Bindable var model = model
    List {
      if isResolving { ProgressView("Opening in Maps…") }
      ForEach(model.results) { result in
        Button {
          Task { await select(result) }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(result.title).font(.headline)
            if !result.subtitle.isEmpty { Text(result.subtitle).font(.subheadline).foregroundStyle(.secondary) }
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain)
      }
    }
    .searchable(text: $model.query, prompt: "Search Apple Maps")
    .navigationTitle("Add place")
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    .alert("Couldn't add place", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  @MainActor
  private func select(_ result: MapPlaceSearchResult) async {
    guard let householdID else { return }
    isResolving = true
    defer { isResolving = false }
    guard let captured = await model.resolve(result) else {
      errorMessage = "Apple Maps couldn't open that result. Try another place."
      return
    }
    do {
      let now = dateNow
      let newID = uuid()
      let kind = PlaceKind(pointOfInterestCategory: captured.pointOfInterestCategory)
      let place = try await database.write { db in
        try PlaceOperations.add(captured, kind: kind, householdID: householdID, now: now, id: newID, in: db)
      }
      model.resultTapped()
      dismiss()
      onAdd(place)
    } catch { errorMessage = error.localizedDescription }
  }
}

private struct PlaceDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @FetchOne var livePlace: Place?
  @FetchAll(PlaceVisit.order(by: \.day)) private var allVisits: [PlaceVisit]
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.date.now) private var dateNow
  @Dependency(\.uuid) private var uuid
  @Shared(.currentPersonID) private var currentPersonIDString
  @State private var name: String
  @State private var kind: PlaceKind
  @State private var standing: PlaceStanding
  @State private var meals: Set<Meal>
  @State private var address: String
  @State private var websiteURL: String
  @State private var note: String
  @State private var showingVisit = false
  @State private var showingDelete = false
  @State private var errorMessage: String?
  @State private var hasEditedStanding = false

  let place: Place
  private var visits: [PlaceVisit] { allVisits.filter { $0.placeID == place.id }.sorted { $0.day > $1.day } }
  private var mapsURL: URL? {
    var components = URLComponents(string: "https://maps.apple.com/")
    components?.queryItems = [
      URLQueryItem(name: "q", value: place.name),
      URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)")
    ]
    return components?.url
  }

  init(place: Place) {
    self.place = place
    _livePlace = FetchOne(wrappedValue: nil, Place.find(place.id))
    _name = State(initialValue: place.name)
    _kind = State(initialValue: place.kind)
    _standing = State(initialValue: place.standing)
    _meals = State(initialValue: place.meals.values)
    _address = State(initialValue: place.address ?? "")
    _websiteURL = State(initialValue: place.websiteURL ?? "")
    _note = State(initialValue: place.note ?? "")
  }

  var body: some View {
    Form {
      Section("Place") {
        TextField("Name", text: $name)
        PlaceKindPicker(selection: $kind)
        TextField("Address", text: $address)
        if let mapsURL { Link("Open in Apple Maps", destination: mapsURL) }
        if let url = URL(string: websiteURL), !websiteURL.isEmpty { Link("Website", destination: url) }
        TextField("Website URL", text: $websiteURL)
        PlaceStandingPicker(selection: $standing)
        if kind == .food {
          ForEach(Meal.allCases, id: \.self) { meal in
            Toggle(meal.title, isOn: Binding(
              get: { meals.contains(meal) }, set: { if $0 { meals.insert(meal) } else { meals.remove(meal) } }
            ))
          }
        }
        TextField("Note", text: $note, axis: .vertical).lineLimit(2...6)
      }
      Section("Visits") {
        Button("Log visit", systemImage: "plus") { showingVisit = true }
        ForEach(visits) { visit in
          VStack(alignment: .leading) {
            Text(visit.day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: Calendar.newYork.timeZone)))
            if let meal = visit.meal { Text(meal.title).font(.caption).foregroundStyle(.secondary) }
            if let note = visit.note, !note.isEmpty { Text(note) }
          }.swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { deleteVisit(visit) }
          }
        }
      }
      Section { Button("Delete place", role: .destructive) { showingDelete = true } }
    }
    .navigationTitle(livePlace?.name ?? place.name)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
    }
    .sheet(isPresented: $showingVisit) {
      NavigationStack {
        if let livePlace {
          LogPlaceVisitView(place: livePlace, onSave: logVisit)
        } else {
          ProgressView("Loading place…")
        }
      }
    }
    .onChange(of: standing) { _, value in
      hasEditedStanding = value != (livePlace?.standing ?? place.standing)
    }
    .onChange(of: livePlace?.standing) { _, value in
      guard !hasEditedStanding, let value else { return }
      standing = value
    }
    .confirmationDialog("Delete \(place.name)?", isPresented: $showingDelete, titleVisibility: .visible) {
      Button("Mark Not for us", role: .destructive) { setStanding(.notForUs) }
      Button("Delete place and visits", role: .destructive) { deletePlace() }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Couldn't save place", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  private func save() {
    let currentPlace = livePlace ?? place
    let shouldUpdateStanding = standing != currentPlace.standing
    let authorID = UUID(uuidString: currentPersonIDString)
    let now = dateNow
    let placeID = place.id
    let updatedName = name
    let updatedKind = kind
    let updatedStanding = standing
    let updatedMeals = Meals(kind == .food ? meals : [])
    let updatedAddress = address.isEmpty ? nil : address
    let updatedWebsiteURL = websiteURL.isEmpty ? nil : websiteURL
    let updatedNote = note.isEmpty ? nil : note
    Task { do {
      try await database.write { db in
        try PlaceOperations.updateDetails(
          name: updatedName, kind: updatedKind, meals: updatedMeals, address: updatedAddress,
          websiteURL: updatedWebsiteURL, note: updatedNote, basedOn: place, updatedAt: now,
          for: placeID, in: db
        )
        if shouldUpdateStanding {
          try PlaceOperations.setStanding(updatedStanding, authorID: authorID, now: now, for: placeID, in: db)
        }
      }
      dismiss()
    }
      catch { errorMessage = error.localizedDescription } }
  }
  private func setStanding(_ value: PlaceStanding) {
    let authorID = UUID(uuidString: currentPersonIDString)
    let now = dateNow
    let placeID = place.id
    Task { do { try await database.write { db in try PlaceOperations.setStanding(value, authorID: authorID, now: now, for: placeID, in: db) }; dismiss() }
      catch { errorMessage = error.localizedDescription } }
  }
  private func logVisit(_ day: Date, _ meal: Meal?, _ visitNote: String, _ verdict: Verdict?) {
    let currentStanding = livePlace?.standing ?? place.standing
    let visit = PlaceVisit(
      id: uuid(), placeID: place.id, day: day, meal: meal, note: visitNote.isEmpty ? nil : visitNote,
      authorID: UUID(uuidString: currentPersonIDString), createdAt: dateNow
    )
    Task { do {
      try await database.write { db in try PlaceOperations.logVisit(visit, verdict: verdict, in: db) }
      if case .toTry = currentStanding { standing = .tried(verdict) }
    }
      catch { errorMessage = error.localizedDescription } }
  }
  private func deleteVisit(_ visit: PlaceVisit) {
    Task { do { try await database.write { db in try PlaceOperations.deleteVisit(visit.id, in: db) } }
      catch { errorMessage = error.localizedDescription } }
  }
  private func deletePlace() {
    Task { do { try await database.write { db in try PlaceOperations.deletePlace(place.id, in: db) }; dismiss() }
      catch { errorMessage = error.localizedDescription } }
  }
}

private struct PlaceKindPicker: View {
  @Binding var selection: PlaceKind
  var body: some View {
    Picker("Kind", selection: $selection) {
      ForEach(PlaceKind.allCases, id: \.self) { kind in
        Text(kind.rawValue.capitalized).tag(kind)
      }
    }
  }
}

private struct PlaceStandingPicker: View {
  @Binding var selection: PlaceStanding
  private let options: [(String, PlaceStanding)] = [
    ("High priority", .toTry(.high)), ("To try", .toTry(.normal)), ("Someday", .toTry(.someday)),
    ("Tried", .tried(nil)), ("Our place", .tried(.ourPlace)), ("Would return", .tried(.wouldReturn)),
    ("Once was enough", .tried(.onceWasEnough)), ("Not for us", .notForUs)
  ]
  var body: some View {
    Picker("Standing", selection: $selection) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Text(option.0).tag(option.1)
      }
    }
  }
}

private struct LogPlaceVisitView: View {
  @Environment(\.dismiss) private var dismiss
  let place: Place
  let onSave: (Date, Meal?, String, Verdict?) -> Void
  @State private var day: Date
  @State private var meal: Meal?
  @State private var note = ""
  @State private var verdict: Verdict?

  init(place: Place, onSave: @escaping (Date, Meal?, String, Verdict?) -> Void) {
    @Dependency(\.date.now) var dateNow
    self.place = place
    self.onSave = onSave
    _day = State(initialValue: dateNow)
  }

  var body: some View {
    Form {
      DatePicker("Day", selection: $day, displayedComponents: .date)
      if place.kind == .food { Picker("Meal", selection: $meal) {
        Text("Not set").tag(Meal?.none)
        ForEach(Meal.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
      } }
      if case .toTry = place.standing {
        Picker("Verdict", selection: $verdict) {
          Text("Decide later").tag(Verdict?.none)
          Text("Our place").tag(Optional(Verdict.ourPlace))
          Text("Would return").tag(Optional(Verdict.wouldReturn))
          Text("Once was enough").tag(Optional(Verdict.onceWasEnough))
        }
      }
      TextField("Note", text: $note, axis: .vertical)
    }
    .environment(\.calendar, Calendar.newYork)
    .environment(\.timeZone, Calendar.newYork.timeZone)
    .navigationTitle("Log visit")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(day, meal, note, verdict); dismiss() } }
    }
  }
}

private extension Calendar {
  static var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
}
