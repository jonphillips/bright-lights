import Dependencies
import BrightLightsChecking
import SQLiteData
import SwiftUI
import BrightLightsSchema
import Sharing

enum AppScreen: String, CaseIterable, Identifiable {
  case whileHere
  case comingUp
  case new
  case capture
  case stays
  case sources

  var id: Self { self }
  var title: String {
    switch self {
    case .whileHere: "While we're here"
    case .comingUp: "Coming up"
    case .new: "New"
    case .capture: "Capture"
    case .stays: "Stays"
    case .sources: "Sources"
    }
  }
  var symbol: String {
    switch self {
    case .whileHere: "moon.stars"
    case .comingUp: "calendar"
    case .new: "tray.full"
    case .capture: "safari"
    case .stays: "house"
    case .sources: "building.2"
    }
  }
}

struct AppContainer: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @SceneStorage("brightLights.selection") private var storedSelection = ""
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @FetchAll(Listing.canonical) private var listings
  @FetchAll private var reactions: [Reaction]
  @FetchAll private var tasteRecords: [TasteRecord]
  @State private var router: AppRouter
  @State private var newPath: [Source.ID] = []
  @State private var filter = WhatsOnFilter.picked
  @State private var browserModel: BrowserModel
  @State private var sourceFixesModel = SourceFixesModel()

  init() {
    let browserModel = BrowserModel()
    _browserModel = State(initialValue: browserModel)
    _router = State(initialValue: AppRouter(browserModel: browserModel))
  }

  private var roundsBadgeCount: Int { RoundsProjection(sources: sources, stays: stays, now: .now).badgeCount }

  var body: some View {
    @Bindable var router = router
    let newBadgeCount = NewProjection(
      listings: listings, sources: sources, reactions: reactions,
      tasteRecordIDs: Set(tasteRecords.map(\.id)), now: .now
    ).total
    Group {
      if horizontalSizeClass == .compact {
        TabView(selection: $router.selection) {
          ForEach(AppScreen.allCases) { screen in
            navigationStack(for: screen)
              .tag(screen as AppScreen?)
              .tabItem { Label(screen.title, systemImage: screen.symbol) }
              .badge(screen == .capture ? roundsBadgeCount : screen == .new ? newBadgeCount : 0)
          }
        }
      } else {
        NavigationSplitView {
          List(AppScreen.allCases, selection: $router.selection) { screen in
            HStack {
              Label(screen.title, systemImage: screen.symbol)
              Spacer()
              if screen == .capture, roundsBadgeCount > 0 {
                Text(roundsBadgeCount.formatted()).font(.caption).foregroundStyle(.secondary)
              } else if screen == .new, newBadgeCount > 0 {
                Text(newBadgeCount.formatted()).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .navigationTitle("Bright Lights")
        } detail: {
          navigationStack(for: router.selection ?? .comingUp)
        }
      }
    }
    .environment(browserModel)
    .environment(sourceFixesModel)
    .environment(router)
    .onAppear {
      if let restored = AppScreen(rawValue: storedSelection) { router.selection = restored }
      else { router.selection = defaultScreen }
    }
    .onChange(of: router.selection) { _, value in storedSelection = value?.rawValue ?? "" }
  }

  @ViewBuilder
  private func destination(for screen: AppScreen) -> some View {
    switch screen {
    case .whileHere: WhatsOnScreen(mode: .whileHere, filter: $filter)
    case .comingUp: WhatsOnScreen(mode: .comingUp, filter: $filter)
    case .new: NewScreen(path: $newPath)
    case .capture: CaptureScreen()
    case .stays: StaysView()
    case .sources: SourcesView()
    }
  }

  @ViewBuilder
  private func navigationStack(for screen: AppScreen) -> some View {
    if screen == .new {
      NavigationStack(path: $newPath) { destination(for: screen) }
    } else {
      NavigationStack { destination(for: screen) }
    }
  }

  private var defaultScreen: AppScreen {
    let hasCurrentStay = WhatsOnProjection.currentStay(in: stays, now: .now, calendar: .current) != nil
    return hasCurrentStay ? .whileHere : .comingUp
  }
}

private enum WhatsOnMode { case whileHere, comingUp }

private struct NewScreen: View {
  @Binding var path: [Source.ID]
  @FetchAll(Listing.canonical.order(by: \.startsAt)) private var listings: [Listing]
  @FetchAll(Source.active.order(by: \.name)) private var sources: [Source]
  @FetchAll private var reactions: [Reaction]
  @FetchAll private var tasteRecords: [TasteRecord]

  var body: some View {
    let projection = NewProjection(
      listings: listings, sources: sources, reactions: reactions,
      tasteRecordIDs: Set(tasteRecords.map(\.id)), now: .now
    )
    Group {
      if projection.groups.isEmpty && path.isEmpty {
        ContentUnavailableView("Nothing new", systemImage: "tray.full")
      } else {
        List(projection.groups) { group in
          NavigationLink(value: group.source.id) {
            HStack {
              Text(group.source.name)
              Spacer()
              Text(group.count.formatted()).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("New")
    .navigationDestination(for: Source.ID.self) { sourceID in
      if let source = sources.first(where: { $0.id == sourceID }) {
        let rows = projection.groups.first(where: { $0.source.id == sourceID })?.listings ?? []
        ScreenList(source: source, listings: rows, tasteRecords: tasteRecords, onDone: { path.removeAll() })
      } else {
        ContentUnavailableView("Source unavailable", systemImage: "building.2")
      }
    }
  }
}

private struct WhatsOnScreen: View {
  let mode: WhatsOnMode
  @Binding var filter: WhatsOnFilter
  @FetchAll private var listings: [Listing]
  @FetchAll(Listing.canonical.where { $0.closesAt.isNot(nil) }) private var runs: [Listing]
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays
  @FetchAll private var reactions: [Reaction]
  @FetchAll(Person.order(by: \.createdAt)) private var people: [Person]
  @Shared(.currentPersonID) private var currentPersonIDString
  @State private var showEverything = false
  @State private var showingPassed = false
  @State private var showingReactionError = false
  @State private var reactionError = ""

  init(mode: WhatsOnMode, filter: Binding<WhatsOnFilter>) {
    self.mode = mode
    _filter = filter
    let calendar = Calendar.newYork
    let start = calendar.startOfDay(for: .now)
    let end = calendar.date(byAdding: .day, value: 60, to: start)!
    _listings = FetchAll(Listing.canonical.where { $0.startsAt.gte(start) && $0.startsAt.lt(end) }.order(by: \.startsAt))
  }

  private var projection: WhatsOnProjection {
    WhatsOnProjection(listings: allListings, sources: sources, stays: stays, reactions: reactions, now: .now, calendar: .current)
  }

  private var allListings: [Listing] {
    Dictionary((listings + runs).map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current }).values.sorted { $0.startsAt < $1.startsAt }
  }

  var body: some View {
    Group {
      if mode == .whileHere {
        whileHereContent
      } else {
        comingUpContent
      }
    }
    .navigationTitle(mode == .whileHere ? "While we're here" : "Coming up")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Show", selection: $filter) {
            ForEach(WhatsOnFilter.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        } label: { Label(filter.title, systemImage: "line.3.horizontal.decrease") }
      }
    }
    .sheet(isPresented: $showingPassed) {
      NavigationStack { PassedListingsView(items: passedItems) }
    }
    .alert("Couldn't save reaction", isPresented: $showingReactionError) {
      Button("OK", role: .cancel) {}
    } message: { Text(reactionError) }
  }

  private var passedItems: [WhatsOnItem] { projection.passedItems }

  @ViewBuilder
  private var whileHereContent: some View {
    if let group = projection.whileHere {
      List {
        if !group.running.isEmpty { itemSection("Running", items: group.running) }
        ForEach(group.days) { day in
          itemSection(dayTitle(day.date), items: projection.filtered(day.items, by: filter))
        }
        passedSection
        if let extraDay = group.extraDay {
          itemSection("If you stay through \(nyWeekdayDate(extraDay.date))", items: projection.filtered(extraDay.items, by: filter))
        }
      }
    } else {
      ContentUnavailableView {
        Label("No current stay", systemImage: "house")
      } description: {
        Text(projection.nextStay.map { "Your next stay starts \(nyDate($0.arrivesOn))." } ?? "No stay planned.")
      } actions: {
        NavigationLink("Add stay", destination: StaysView(showEditorOnAppear: true))
      }
    }
  }

  private var comingUpContent: some View {
    List {
      if !projection.deadlines.onSale.isEmpty || !projection.deadlines.closing.isEmpty {
        Section("Deadlines") {
          ForEach(projection.deadlines.onSale) { item in
            NavigationLink { ListingDetailView(item: item) } label: {
              VStack(alignment: .leading) {
                Text("On sale \(nyDate(item.listing.onSaleAt!)): \(item.listing.title)")
                Text(item.sourceName).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          ForEach(projection.deadlines.closing, id: \.item.id) { deadline in
            NavigationLink { ListingDetailView(item: deadline.item) } label: {
              VStack(alignment: .leading) {
                Text("Closes \(nyDate(deadline.item.listing.closesAt!)) — \(closingNote(deadline.staysBeforeClose))")
                Text(deadline.item.listing.title).font(.subheadline)
              }
            }
          }
        }
      }
      Toggle("Show everything", isOn: $showEverything)
      if !showEverything {
        ForEach(projection.comingUp) { group in
          Section {
            if let note = group.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if !group.running.isEmpty { itemRows(group.running) }
            ForEach(group.days) { day in
              DisclosureGroup(dayTitle(day.date)) { itemRows(projection.filtered(day.items, by: filter)) }
            }
          } header: { Text(group.title) }
        }
      }
      if showEverything {
        ForEach(projection.showEverythingByWeek) { group in
          Section(group.title) {
            itemRows(projection.filtered(group.days.flatMap(\.items), by: filter))
          }
        }
      }
      if projection.comingUp.isEmpty { ContentUnavailableView("Nothing in the next 60 days", systemImage: "calendar") }
      passedSection
    }
  }

  private var passedSection: some View {
    Group {
      if projection.passedCount > 0 {
        Button("\(projection.passedCount) passed") { showingPassed = true }
      }
    }
  }

  private func itemSection(_ title: String, items: [WhatsOnItem]) -> some View {
    Section(title) { itemRows(items) }
  }

  private func itemRows(_ items: [WhatsOnItem]) -> some View {
    ForEach(projection.filtered(items, by: filter)) { item in
      NavigationLink { ListingDetailView(item: item) } label: {
        ListingRow(
          item: item,
          authorName: item.reaction.flatMap { reaction in people.first { $0.id == reaction.authorID }?.displayName },
          isCurrentPerson: item.reaction?.authorID == UUID(uuidString: currentPersonIDString)
        )
      }
        .contextMenu { reactionActions(for: item) }
        .swipeActions(edge: .trailing) {
          Button { setReaction(.booked, for: item) } label: { Label("Booked", systemImage: "ticket") }.tint(.green)
          Button { setReaction(.interested, for: item) } label: { Label("Interested", systemImage: "heart") }.tint(.blue)
        }
    }
  }

  @ViewBuilder private func reactionActions(for item: WhatsOnItem) -> some View {
    Button("Interested") { setReaction(.interested, for: item) }
    Button("Booked") { setReaction(.booked, for: item) }
    Button("Pass") { setReaction(.pass, for: item) }
    if item.listing.startsAt <= .now { Button("Went") { setReaction(.went, for: item) } }
    if item.reaction == nil {
      Button("Clear") { setReaction(.cleared, for: item) }
    } else {
      Button("Remove reaction") { setReaction(.kept, for: item) }
    }
  }

  private func setReaction(_ kind: ReactionKind, for item: WhatsOnItem) {
    @Dependency(\.defaultDatabase) var database
    let reaction = Reaction(
      id: UUID(), listingID: item.listing.id, kind: kind, note: item.reaction?.note,
      authorID: UUID(uuidString: currentPersonIDString), updatedAt: .now
    )
    Task {
      do { try await database.write { db in try Reaction.upsertForListing(reaction, in: db) } }
      catch { reactionError = error.localizedDescription; showingReactionError = true }
    }
  }

  private func dayTitle(_ date: Date) -> String {
    let calendar = Calendar.newYork
    if calendar.isDateInToday(date) { return "Tonight" }
    if calendar.isDateInTomorrow(date) { return "Tomorrow" }
    return nyWeekdayDate(date)
  }

  private func closingNote(_ count: Int) -> String {
    switch count {
    case 0: "before your next stay"
    case 1: "your last stay before it closes"
    default: "\(count) stays before it closes"
    }
  }
}

private struct ListingRow: View {
  let item: WhatsOnItem
  let authorName: String?
  let isCurrentPerson: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(item.listing.title).font(.headline)
        Spacer()
        if let reaction = item.reaction {
          Image(systemName: reactionSymbol(reaction.kind))
          Text(Reaction.attributedTitle(
            kind: reaction.kind,
            authorName: authorName,
            isCurrentPerson: isCurrentPerson
          )).font(.caption).foregroundStyle(.secondary)
        }
      }
      Text("\(nyTime(item.listing.startsAt))\(TimeZone.current.identifier == "America/New_York" ? "" : " ET") · \(item.sourceName)\(item.listing.room.map { " · \($0)" } ?? "")")
        .font(.subheadline).foregroundStyle(.secondary)
      if let badge = item.badge { Text(badge).font(.caption).foregroundStyle(.orange) }
    }
    .padding(.vertical, 3)
  }
}

private struct ListingDetailView: View {
  @Environment(AppRouter.self) private var router
  let item: WhatsOnItem
  @FetchAll private var reactions: [Reaction]
  @State private var note: String
  @State private var showingError = false
  @State private var errorMessage = ""
  @Shared(.currentPersonID) private var currentPersonIDString

  init(item: WhatsOnItem) {
    self.item = item
    _reactions = FetchAll(Reaction.where { $0.listingID.eq(item.listing.id) })
    _note = State(initialValue: item.reaction?.note ?? "")
  }

  private var currentReaction: Reaction? { WhatsOnProjection.latestReaction(in: reactions) }

  var body: some View {
    Form {
      Section(item.listing.title) {
        LabeledContent("Venue", value: item.sourceName)
        if let room = item.listing.room { LabeledContent("Room", value: room) }
        LabeledContent("Performers", value: ListingDisplay.performerNames(item.listing.performers))
        LabeledContent("When", value: item.listing.closesAt.map { "\(ListingDisplay.newYorkDateTime(item.listing.startsAt)) – \(ListingDisplay.newYorkDateTime($0))" } ?? ListingDisplay.newYorkDateTime(item.listing.startsAt))
        LabeledContent("Status", value: item.badge ?? item.listing.status.rawValue.capitalized)
        if let onSale = item.listing.onSaleAt { LabeledContent("On sale", value: ListingDisplay.newYorkDateTime(onSale)) }
        if let url = item.listing.ticketURL.flatMap(URL.init(string:)) {
          Button { router.capture(url) } label: { Label("Tickets", systemImage: "ticket") }
        }
      }
      Section("Your reaction") {
        ForEach([ReactionKind.kept, .interested, .booked, .went, .pass], id: \.self) { kind in
          Button { save(kind) } label: {
            HStack {
              Text(kind.title)
              Spacer()
              if currentReaction?.kind == kind { Image(systemName: "checkmark.circle.fill") }
            }
          }.disabled(kind == .went && item.listing.startsAt > .now)
        }
        TextField("Note", text: $note, axis: .vertical)
        if currentReaction == nil {
          Text("Pick a reaction to add a note").font(.caption).foregroundStyle(.secondary)
        }
        Button("Save note") { saveNote() }
          .disabled(currentReaction == nil)
        if currentReaction != nil {
          Button("Remove reaction") { save(.kept) }
        } else {
          Button("Clear") { save(.cleared) }
        }
      }
    }
    .navigationTitle(item.listing.title)
    .alert("Couldn't save reaction", isPresented: $showingError) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
    .onChange(of: currentReaction?.note) { _, value in note = value ?? "" }
  }

  private func save(_ kind: ReactionKind) {
    @Dependency(\.defaultDatabase) var database
    let reaction = Reaction(
      id: currentReaction?.id ?? UUID(), listingID: item.listing.id, kind: kind,
      note: note.isEmpty ? nil : note,
      authorID: UUID(uuidString: currentPersonIDString),
      updatedAt: .now
    )
    Task {
      do { try await database.write { db in try Reaction.upsertForListing(reaction, in: db) } }
      catch { errorMessage = error.localizedDescription; showingError = true }
    }
  }

  private func saveNote() {
    guard let kind = currentReaction?.kind else { return }
    save(kind)
  }

}

private struct PassedListingsView: View {
  @FetchAll(Person.order(by: \.createdAt)) private var people: [Person]
  @Shared(.currentPersonID) private var currentPersonIDString
  let items: [WhatsOnItem]
  var body: some View {
    List(items) { item in
      NavigationLink { ListingDetailView(item: item) } label: {
        ListingRow(
          item: item,
          authorName: item.reaction.flatMap { reaction in people.first { $0.id == reaction.authorID }?.displayName },
          isCurrentPerson: item.reaction?.authorID == UUID(uuidString: currentPersonIDString)
        )
      }
    }
      .navigationTitle("Passed")
  }
}

private extension Calendar {
  static var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
}

private func nyTime(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = Calendar.newYork.timeZone
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

private func nyDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = Calendar.newYork.timeZone
  formatter.dateStyle = .medium
  formatter.timeStyle = .none
  return formatter.string(from: date)
}

private func nyWeekdayDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = Calendar.newYork.timeZone
  formatter.dateFormat = "EEEE, MMM d"
  return formatter.string(from: date)
}

private func reactionSymbol(_ reaction: ReactionKind) -> String {
  switch reaction {
  case .kept: "checkmark"
  case .interested: "heart.fill"
  case .booked: "ticket.fill"
  case .went: "checkmark.circle.fill"
  case .pass: "eye.slash"
  case .cleared: "xmark"
  }
}
