import Dependencies
import SQLiteData
import SwiftUI
import BrightLightsSchema

struct StaysView: View {
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays
  @State private var editingStay: Stay?
  @State private var isCreating = false
  @State private var deletingStay: Stay?
  @State private var showingDeleteConfirmation = false
  @State private var showPast = false
  @State private var showingDeleteError = false
  @State private var deleteError = ""

  init(showEditorOnAppear: Bool = false) {
    if showEditorOnAppear { _isCreating = State(initialValue: true) }
  }

  private var future: [Stay] { stays.filter { Calendar.newYork.startOfDay(for: $0.arrivesOn) >= Calendar.newYork.startOfDay(for: .now) } }
  private var past: [Stay] { stays.filter { stay in !future.contains(where: { $0.id == stay.id }) } }

  var body: some View {
    List {
      Section("Upcoming and current") {
        if future.isEmpty {
          ContentUnavailableView("No stays planned", systemImage: "house", description: Text("Add a stay to see what's on while you're in New York."))
        }
        ForEach(future) { stay in stayRow(stay) }
      }
      if !past.isEmpty {
        Section {
          DisclosureGroup("Past stays (\(past.count))", isExpanded: $showPast) {
            ForEach(past.reversed()) { stay in stayRow(stay) }
          }
        }
      }
    }
    .navigationTitle("Stays")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { isCreating = true } label: { Label("Add stay", systemImage: "plus") }
      }
    }
    .sheet(isPresented: $isCreating) { StayEditorView(stay: nil, stays: stays) }
    .sheet(item: $editingStay) { stay in StayEditorView(stay: stay, stays: stays) }
    .confirmationDialog("Delete this stay?", isPresented: $showingDeleteConfirmation, presenting: deletingStay) { stay in
      Button("Delete Stay", role: .destructive) { delete(stay) }
      Button("Cancel", role: .cancel) {}
    } message: { stay in Text("Listings and reactions will stay in Bright Lights.") }
    .alert("Couldn't delete stay", isPresented: $showingDeleteError) {
      Button("OK", role: .cancel) {}
    } message: { Text(deleteError) }
  }

  private func stayRow(_ stay: Stay) -> some View {
    Button { editingStay = stay } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(stayTitle(stay)).font(.headline)
        Text(stay.departureKind == .booked ? "Booked" : stay.departureKind == .tentative ? "Tentative" : "Open departure")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Edit stay", systemImage: "pencil") { editingStay = stay }
      Button("Delete stay", systemImage: "trash", role: .destructive) {
        deletingStay = stay
        showingDeleteConfirmation = true
      }
    }
  }

  private func stayTitle(_ stay: Stay) -> String {
    let arrival = nyMonthDay(stay.arrivesOn)
    guard let end = stay.departsOn else { return "\(arrival)–Open" }
    return "\(arrival)–\(nyMonthDay(end))"
  }

  private func delete(_ stay: Stay) {
    @Dependency(\.defaultDatabase) var database
    Task {
      do { try await database.write { db in try Stay.find(stay.id).delete().execute(db) } }
      catch { deleteError = error.localizedDescription; showingDeleteError = true }
    }
  }
}

private func nyMonthDay(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeZone = Calendar.newYork.timeZone
  formatter.dateFormat = "MMM d"
  return formatter.string(from: date)
}

private struct StayEditorView: View {
  let stay: Stay?
  let stays: [Stay]
  @Environment(\.dismiss) private var dismiss
  @State private var arrival: Date
  @State private var departureKind: StayDepartureKind
  @State private var departure: Date
  @State private var showingError = false
  @State private var errorMessage = ""

  init(stay: Stay?, stays: [Stay]) {
    self.stay = stay
    self.stays = stays
    _arrival = State(initialValue: stay?.arrivesOn ?? .now)
    _departureKind = State(initialValue: stay?.departureKind ?? .booked)
    _departure = State(initialValue: stay?.departsOn ?? Calendar.newYork.date(byAdding: .day, value: 7, to: .now)!)
  }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker("Arrive", selection: $arrival, displayedComponents: .date)
        Picker("Departure", selection: $departureKind) {
          Text("Booked").tag(StayDepartureKind.booked)
          Text("Tentative").tag(StayDepartureKind.tentative)
          Text("Open").tag(StayDepartureKind.open)
        }
        if departureKind != .open {
          DatePicker("Leave", selection: $departure, in: departureRangeStart..., displayedComponents: .date)
        }
      }
      .environment(\.calendar, Calendar.newYork)
      .environment(\.timeZone, Calendar.newYork.timeZone)
      .navigationTitle(stay == nil ? "New stay" : "Edit stay")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
      }
      .alert("Stay couldn't be saved", isPresented: $showingError) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
    }
  }

  private var departureRangeStart: Date {
    StayRules.normalized(arrival, calendar: Calendar.newYork)
  }

  private func save() {
    let calendar = Calendar.newYork
    let arrival = StayRules.normalized(arrival, calendar: calendar)
    let normalizedDeparture = StayRules.normalized(departure, calendar: calendar)
    let value: StayDeparture
    switch departureKind {
    case .booked: value = .booked(normalizedDeparture)
    case .tentative: value = .tentative(normalizedDeparture)
    case .open: value = .open
    }
    do {
      try StayRules.validate(arrival: arrival, departure: value, editing: stay?.id, against: stays, calendar: calendar)
    } catch StayValidationError.departureBeforeArrival {
      errorMessage = "Departure can't be before arrival."
      showingError = true
      return
    } catch let StayValidationError.overlaps(id) {
      let other = stays.first { $0.id == id }
      errorMessage = "This stay overlaps \(other.map { nyMonthDay($0.arrivesOn) } ?? "another stay")."
      showingError = true
      return
    } catch {
      errorMessage = error.localizedDescription
      showingError = true
      return
    }
    @Dependency(\.defaultDatabase) var database
    Task {
      do {
        let id = stay?.id ?? UUID()
        try await database.write { db in
          let household = try Household.ensureDefault(in: db)
          let updated = Stay(id: id, householdID: stay?.householdID ?? household.id, arrivesOn: arrival, departure: value)
          try Stay.upsert { Stay.Draft(updated) }.execute(db)
        }
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        showingError = true
      }
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
