import BrightLightsPlaces
import BrightLightsSchema
import Dependencies
import MapKit
import MapPlacesKit
import SQLiteData
import Sharing
import SwiftUI

struct PlacesView: View {
  @FetchAll private var households: [Household]
  @FetchAll(Place.order(by: \.name)) private var places: [Place]
  @FetchAll(PlaceVisit.order(by: \.day)) private var visits: [PlaceVisit]
  @FetchAll(SyncMetadata.where { $0.recordType.eq("households") }) private var metadata: [SyncMetadata]
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.date.now) private var dateNow
  @Dependency(\.uuid) private var uuid
  @State private var placeForDetail: Place?
  @State private var showingSearch = false
  @State private var selectedPlaceID: Place.ID?
  @State private var mapCamera: MapCameraPosition = .region(Self.initialMapRegion)
  @State private var mapSelection: MapSelection<Place.ID>?
  @State private var selectedMapItem: MKMapItem?
  @State private var compactPresentation: PlacePane = .list
  @State private var mapPressStartedAt: Date?
  @State private var mapPressStartLocation: CGPoint?
  @State private var errorMessage: String?
  @Shared(.appStorage("brightLightsPlaceKindFilter")) private var kindFilterRaw = PlaceFilter.Kind.all.rawValue
  @Shared(.appStorage("brightLightsPlaceMealFilter")) private var mealFilterRaw = PlaceFilter.MealChoice.any.rawValue
  @Shared(.appStorage("brightLightsPlaceStandingFilter")) private var standingFilterRaw = PlaceFilter.Standing.everything.rawValue
  @Shared(.appStorage("brightLightsShowNotForUsPlaces")) private var includesNotForUs = false
  @Shared(.appStorage("brightLightsHideOutOfSeason")) private var hidesOutOfSeason = false

  private static let initialMapRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 40.72, longitude: -73.96),
    span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22)
  )

  private var household: Household? {
    guard !households.isEmpty else { return nil }
    return Household.survivor(in: households) { Household.sharingState(of: $0, metadata: metadata) }
  }
  private var projection: PlaceCheckSheet {
    PlaceCheckSheet(places: householdPlaces, visits: visits, filter: placeFilter, today: dateNow)
  }

  private var placeFilter: PlaceFilter {
    PlaceFilter(
      kind: kindFilter, meal: mealFilter, standing: standingFilter,
      includesNotForUs: includesNotForUs, hidesOutOfSeason: hidesOutOfSeason, today: dateNow
    )
  }
  private var kindFilter: PlaceFilter.Kind {
    get { PlaceFilter.Kind(rawValue: kindFilterRaw) ?? .all }
    nonmutating set { $kindFilterRaw.withLock { $0 = newValue.rawValue } }
  }
  private var mealFilter: PlaceFilter.MealChoice {
    get { PlaceFilter.MealChoice(rawValue: mealFilterRaw) ?? .any }
    nonmutating set { $mealFilterRaw.withLock { $0 = newValue.rawValue } }
  }
  private var standingFilter: PlaceFilter.Standing {
    get { PlaceFilter.Standing(rawValue: standingFilterRaw) ?? .everything }
    nonmutating set { $standingFilterRaw.withLock { $0 = newValue.rawValue } }
  }
  private var isFoodSelected: Bool { kindFilter == .food }
  private var householdPlaces: [Place] { places.filter { $0.householdID == household?.id } }
  private var filteredPlaces: [Place] { projection.filteredPlaces }

  var body: some View {
    VStack(spacing: 0) {
      filterBar
      if horizontalSizeClass == .compact {
        Picker("Places view", selection: $compactPresentation) {
          ForEach(PlacePane.allCases) { pane in Text(pane.title).tag(pane) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        if compactPresentation == .list { placeList } else { mapPane }
      } else {
        HStack(spacing: 0) {
          placeList.frame(minWidth: 320, idealWidth: 390, maxWidth: 480)
          Divider()
          mapPane
        }
      }
    }
    .navigationTitle("Places")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
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
    .task(id: mapSelection) { await handleMapSelection() }
  }

  private var placeList: some View {
    List {
      if household == nil {
        ContentUnavailableView("Places unavailable", systemImage: "mappin.and.ellipse")
      } else {
        if projection.missingMealsCount > 0 {
          Section {
            HStack(alignment: .firstTextBaseline) {
              Text("\(projection.missingMealsCount) food places have no meals set")
                .font(.subheadline).foregroundStyle(.secondary)
              Spacer(minLength: 8)
              Button("Fill them in") {
                if let place = projection.placesMissingMeals.first { placeForDetail = place }
              }
              .font(.subheadline.weight(.semibold))
            }
          }
        }
        if projection.groups.isEmpty {
          ContentUnavailableView {
            Label("No places", systemImage: "mappin.and.ellipse")
          } description: {
            Text("Try another filter or add a place from Apple Maps.")
          } actions: {
            Button("Add place", systemImage: "plus") { showingSearch = true }
              .buttonStyle(.borderedProminent)
          }
        } else {
          ForEach(projection.groups) { group in
            Section(group.title) {
              ForEach(group.rows) { row in
                Button {
                  selectedPlaceID = row.place.id
                  placeForDetail = row.place
                } label: {
                  PlaceCheckSheetRowView(row: row)
                    .padding(.vertical, 3)
                    .background(selectedPlaceID == row.place.id ? Color.accentColor.opacity(0.08) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedPlaceID == row.place.id ? Color.accentColor.opacity(0.08) : nil)
              }
            }
          }
        }
      }
    }
    .modifier(PlacesListStyleModifier())
  }

  private func markerTint(for place: Place) -> Color {
    let base = place.id == selectedPlaceID ? Color.orange : (place.standing == .notForUs ? Color.gray : Color.accentColor)
    switch PlaceSeason.resolve(place.when, today: dateNow) {
    case .outOfSeason, .ended: return base.opacity(0.5)
    default: return base
    }
  }

  private var filterBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(PlaceFilter.Kind.allCases, id: \.self) { filter in
            PlaceKindFilterButton(filter: filter, isSelected: kindFilter == filter) {
              kindFilter = filter
            }
          }
        }
        .padding(.horizontal)
      }
      .scrollIndicators(.hidden)
      HStack(spacing: 10) {
        Picker("Standing", selection: Binding(get: { standingFilter }, set: { standingFilter = $0 })) {
          ForEach(PlaceFilter.Standing.allCases, id: \.self) { filter in Text(filter.title).tag(filter) }
        }
        .pickerStyle(.segmented)
        if isFoodSelected {
          Menu {
            ForEach(PlaceFilter.MealChoice.visibleCases, id: \.self) { filter in
              Button {
                mealFilter = filter
              } label: {
                if mealFilter == filter { Label(filter.title, systemImage: "checkmark") }
                else { Text(filter.title) }
              }
            }
          } label: {
            Label(mealFilter.title, systemImage: "chevron.down")
              .font(.subheadline.weight(.medium))
              .padding(.horizontal, 10).padding(.vertical, 7)
              .background(.quaternary, in: Capsule())
          }
          Menu("More") {
            ForEach(PlaceFilter.MealChoice.moreCases, id: \.self) { filter in
              Button {
                mealFilter = filter
              } label: {
                if mealFilter == filter { Label(filter.title, systemImage: "checkmark") }
                else { Text(filter.title) }
              }
            }
            Divider()
            Toggle("Not for us", isOn: Binding(
              get: { includesNotForUs }, set: { newValue in $includesNotForUs.withLock { $0 = newValue } }
            ))
            Toggle("Hide out of season", isOn: Binding(
              get: { hidesOutOfSeason }, set: { newValue in $hidesOutOfSeason.withLock { $0 = newValue } }
            ))
          }
          .fixedSize()
        } else {
          Menu("More") {
            Toggle("Not for us", isOn: Binding(
              get: { includesNotForUs }, set: { newValue in $includesNotForUs.withLock { $0 = newValue } }
            ))
            Toggle("Hide out of season", isOn: Binding(
              get: { hidesOutOfSeason }, set: { newValue in $hidesOutOfSeason.withLock { $0 = newValue } }
            ))
          }
            .fixedSize()
        }
      }
      .padding(.horizontal)
    }
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var mapPane: some View {
    VStack(spacing: 0) {
      if selectedMapItem != nil {
        HStack {
          Spacer()
          Button("Add place", systemImage: "plus") {
            Task { await addSelectedMapItem() }
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
      }
      MapReader { proxy in
        Map(position: $mapCamera, selection: $mapSelection) {
          ForEach(filteredPlaces) { place in
            Marker(place.name, systemImage: place.kind.symbol,
              coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
              .tint(markerTint(for: place))
              .tag(place.id)
          }
        }
        .modifier(MapPOIDetailModifier(selectedMapItem: $selectedMapItem))
        .coordinateSpace(name: "places-map")
        .simultaneousGesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .named("places-map"))
            .onChanged { value in
              if mapPressStartedAt == nil {
                mapPressStartedAt = .now
                mapPressStartLocation = value.startLocation
              }
            }
            .onEnded { value in
              defer {
                mapPressStartedAt = nil
                mapPressStartLocation = nil
              }
              guard let startedAt = mapPressStartedAt,
                    let start = mapPressStartLocation,
                    Date.now.timeIntervalSince(startedAt) >= 0.8,
                    hypot(value.location.x - start.x, value.location.y - start.y) <= 12,
                    let coordinate = proxy.convert(value.location, from: .named("places-map"))
              else { return }
              Task { await addDroppedPin(at: coordinate) }
            }
        )
        .overlay(alignment: .bottomLeading) {
          Text("Tap a Maps place to explore · press and hold to drop a pin")
            .font(.caption).foregroundStyle(.primary)
            .padding(8).background(.regularMaterial, in: Capsule()).padding(10)
            .allowsHitTesting(false)
        }
      }
    }
    .overlay {
      if filteredPlaces.isEmpty && household != nil {
        ContentUnavailableView("No places on the map", systemImage: "map",
          description: Text("Adjust the filters or tap an Apple Maps place to add one."))
          .allowsHitTesting(false)
      }
    }
  }

  @MainActor
  private func handleMapSelection() async {
    guard let mapSelection else { return }
    if let id = mapSelection.value {
      selectedPlaceID = id
      if let place = filteredPlaces.first(where: { $0.id == id }) {
        placeForDetail = place
      }
    } else if let feature = mapSelection.feature, feature.kind == .pointOfInterest {
      selectedMapItem = await MapPlaceResolver.mapItem(for: feature)
    }
    self.mapSelection = nil
  }

  @MainActor
  private func addSelectedMapItem() async {
    guard let selectedMapItem else { return }
    let captured = MapPlaceResolver.place(for: selectedMapItem)
    self.selectedMapItem = nil
    await Task.yield()
    await add(captured)
  }

  @MainActor
  private func addDroppedPin(at coordinate: CLLocationCoordinate2D) async {
    let captured = MapPlace(
      id: uuid(), name: "Dropped pin", latitude: coordinate.latitude, longitude: coordinate.longitude
    )
    await add(captured)
  }

  @MainActor
  private func add(_ captured: MapPlace) async {
    guard let householdID = household?.id else { return }
    do {
      let now = dateNow
      let place = try await database.write { db in
        try PlaceOperations.add(
          captured, kind: PlaceKind(pointOfInterestCategory: captured.pointOfInterestCategory),
          householdID: householdID, now: now, id: captured.id, in: db
        )
      }
      selectedPlaceID = place.id
      placeForDetail = place
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct MapPOIDetailModifier: ViewModifier {
  @Binding var selectedMapItem: MKMapItem?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    #if os(iOS)
      if horizontalSizeClass == .regular {
        content
          .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
          .mapFeatureSelectionAccessory(nil)
          .mapItemDetailPopover(
            item: $selectedMapItem, attachmentAnchor: .rect(.bounds), arrowEdge: .leading
          )
      } else {
        content
          .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
          .mapFeatureSelectionAccessory(nil)
          .mapItemDetailSheet(item: $selectedMapItem)
      }
    #else
      content
    #endif
  }
}

private struct PlacesListStyleModifier: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
      content.listStyle(.insetGrouped)
    #else
      content.listStyle(.automatic)
    #endif
  }
}

private enum PlacePane: String, CaseIterable, Identifiable {
  case list
  case map
  var id: Self { self }
  var title: String { rawValue.capitalized }
}

private struct PlaceKindFilterButton: View {
  let filter: PlaceFilter.Kind
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(filter.title)
    }
    .buttonStyle(.bordered)
    .tint(isSelected ? Color.accentColor : Color.secondary)
    .controlSize(.small)
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
    switch row.season {
    case .always, .inSeason: break
    case let .outOfSeason(nextOn): parts.append("Next on \(shortNYDate(nextOn))")
    case let .ended(on): parts.append("Ended \(shortNYDate(on))")
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

struct PlaceDetailView: View {
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
  @State private var whenKind: PlaceWhenKind
  @State private var fromMonthDay: MonthDay
  @State private var toMonthDay: MonthDay
  @State private var onceStart: Date
  @State private var onceEnd: Date
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
    switch place.when {
    case .always:
      _whenKind = State(initialValue: .always)
      _fromMonthDay = State(initialValue: MonthDay(month: 1, day: 1))
      _toMonthDay = State(initialValue: MonthDay(month: 1, day: 1))
      _onceStart = State(initialValue: .now)
      _onceEnd = State(initialValue: .now)
    case let .yearly(from, to):
      _whenKind = State(initialValue: .yearly)
      _fromMonthDay = State(initialValue: from)
      _toMonthDay = State(initialValue: to)
      _onceStart = State(initialValue: .now)
      _onceEnd = State(initialValue: .now)
    case let .once(from, to):
      _whenKind = State(initialValue: .once)
      _fromMonthDay = State(initialValue: MonthDay(month: 1, day: 1))
      _toMonthDay = State(initialValue: MonthDay(month: 1, day: 1))
      _onceStart = State(initialValue: from)
      _onceEnd = State(initialValue: to)
    }
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
      Section("When") {
        Picker("Season", selection: $whenKind) {
          Text("Always").tag(PlaceWhenKind.always)
          Text("Every year").tag(PlaceWhenKind.yearly)
          Text("Once").tag(PlaceWhenKind.once)
        }
        if whenKind == .yearly {
          MonthDayPicker(title: "From", selection: $fromMonthDay)
          MonthDayPicker(title: "To", selection: $toMonthDay)
        } else if whenKind == .once {
          DatePicker("Starts", selection: $onceStart, displayedComponents: .date)
          DatePicker("Ends", selection: $onceEnd, in: onceStart..., displayedComponents: .date)
        }
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
    .environment(\.calendar, .newYork)
    .environment(\.timeZone, Calendar.newYork.timeZone)
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
    let updatedWhen: PlaceWhen
    switch whenKind {
    case .always: updatedWhen = .always
    case .yearly: updatedWhen = .yearly(from: fromMonthDay, to: toMonthDay)
    case .once:
      updatedWhen = .once(
        from: StayRules.normalized(onceStart, calendar: .newYork),
        to: StayRules.normalized(max(onceStart, onceEnd), calendar: .newYork)
      )
    }
    Task { do {
      try await database.write { db in
        try PlaceOperations.updateDetails(
          name: updatedName, kind: updatedKind, meals: updatedMeals, address: updatedAddress,
          websiteURL: updatedWebsiteURL, note: updatedNote, when: updatedWhen, basedOn: place, updatedAt: now,
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

private struct MonthDayPicker: View {
  let title: String
  @Binding var selection: MonthDay
  private let months = Calendar.newYork.monthSymbols
  private var daysInMonth: Int {
    var components = DateComponents()
    components.year = 2024
    components.month = selection.month
    return Calendar.newYork.range(of: .day, in: .month, for: Calendar.newYork.date(from: components)!)!.count
  }

  var body: some View {
    HStack {
      Picker("\(title) month", selection: Binding(
        get: { selection.month },
        set: { month in selection = MonthDay(month: month, day: min(selection.day, daysIn(month))) }
      )) {
        ForEach(1...12, id: \.self) { month in Text(months[month - 1]).tag(month) }
      }
      Picker("\(title) day", selection: Binding(
        get: { selection.day }, set: { selection = MonthDay(month: selection.month, day: $0) }
      )) {
        ForEach(1...daysInMonth, id: \.self) { day in Text("\(day)").tag(day) }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func daysIn(_ month: Int) -> Int {
    var components = DateComponents()
    components.year = 2024
    components.month = month
    return Calendar.newYork.range(of: .day, in: .month, for: Calendar.newYork.date(from: components)!)!.count
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

private func shortNYDate(_ date: Date) -> String {
  date.formatted(Date.FormatStyle(timeZone: Calendar.newYork.timeZone).month(.abbreviated).day())
}
