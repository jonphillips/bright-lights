import BrightLightsSchema
import BrightLightsTaste
import Dependencies
import SQLiteData
import Sharing
import SwiftUI

struct TasteNotesView: View {
  @FetchAll private var households: [Household]
  @FetchAll private var notes: [TasteNote]
  @FetchAll private var people: [Person]
  @FetchAll(SyncMetadata.where { $0.recordType.eq("households") }) private var householdMetadata: [SyncMetadata]
  @Dependency(\.defaultDatabase) private var database
  @State private var destination: TasteNoteDestination?
  @State private var errorMessage: String?
  @Shared(.currentPersonID) private var currentPersonIDString

  private var currentPersonID: UUID? { UUID(uuidString: currentPersonIDString) }
  private var household: Household? {
    guard !households.isEmpty else { return nil }
    return Household.survivor(in: households) {
      Household.sharingState(of: $0, metadata: householdMetadata)
    }
  }
  private var visibleNotes: [TasteNote] {
    guard let household else { return [] }
    return notes.filter { $0.householdID == household.id }.sorted {
      if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  var body: some View {
    List {
      if household == nil {
        ContentUnavailableView("Taste notes unavailable", systemImage: "text.quote")
      } else if visibleNotes.isEmpty {
        ContentUnavailableView("No taste notes", systemImage: "text.quote", description: Text("Add a note about a performer, venue, or kind of show."))
      } else {
        ForEach(visibleNotes) { note in
          noteRow(note)
            .swipeActions(edge: .trailing) {
              if note.isEditable(by: currentPersonID) {
                Button(role: .destructive) { delete(note) } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
        }
      }
    }
    .navigationTitle("Taste notes")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { addNote() } label: { Label("Add taste note", systemImage: "plus") }
          .disabled(household == nil)
      }
    }
    .sheet(item: $destination) { destination in
      NavigationStack { TasteNoteEditorView(destination: destination) }
    }
    .alert("Couldn't delete taste note", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  @ViewBuilder
  private func noteRow(_ note: TasteNote) -> some View {
    if note.isEditable(by: currentPersonID) {
      Button { destination = .edit(note) } label: { TasteNoteRow(note: note, authorName: authorName(for: note)) }
        .buttonStyle(.plain)
    } else {
      TasteNoteRow(note: note, authorName: authorName(for: note))
    }
  }

  private func authorName(for note: TasteNote) -> String {
    guard let authorID = note.authorID else { return "No author" }
    guard let person = people.first(where: { $0.id == authorID }) else { return "Unknown person" }
    return person.displayName.isEmpty ? "Unnamed person" : person.displayName
  }

  private func addNote() {
    guard let household else { return }
    destination = .create(householdID: household.id, subject: nil)
  }

  private func delete(_ note: TasteNote) {
    guard note.isEditable(by: currentPersonID) else { return }
    Task {
      do {
        try await database.write { db in
          try TasteNote.find(note.id).delete().execute(db)
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct TasteNoteRow: View {
  let note: TasteNote
  let authorName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let subject = note.subject, !subject.isEmpty {
        Text(subject).font(.headline)
      }
      Text(note.body)
      Text("\(authorName) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum TasteNoteDestination: Identifiable {
  case create(householdID: UUID, subject: String?)
  case edit(TasteNote)

  var id: String {
    switch self {
    case let .create(householdID, subject): "new-\(householdID.uuidString)-\(subject ?? "")"
    case let .edit(note): "edit-\(note.id.uuidString)"
    }
  }

  var householdID: UUID {
    switch self {
    case let .create(householdID, _): householdID
    case let .edit(note): note.householdID
    }
  }

  var note: TasteNote? {
    guard case let .edit(note) = self else { return nil }
    return note
  }

  var subject: String? {
    guard case let .create(_, subject) = self else { return nil }
    return subject
  }
}

struct TasteNoteEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.date.now) private var dateNow
  @Dependency(\.uuid) private var uuid
  @Shared(.currentPersonID) private var currentPersonIDString
  @State private var draft: TasteNoteFormDraft
  @State private var isSaving = false
  @State private var errorMessage: String?

  let destination: TasteNoteDestination

  init(destination: TasteNoteDestination) {
    self.destination = destination
    let note = destination.note
    _draft = State(initialValue: TasteNoteFormDraft(
      subject: note?.subject ?? destination.subject ?? "",
      body: note?.body ?? ""
    ))
  }

  private var isBodyEmpty: Bool {
    draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    Form {
      Section {
        StackedFormField(title: "Subject") {
          TextField("Subject", text: $draft.subject)
        }
        StackedFormField(title: "Note") {
          TextEditor(text: $draft.body)
            .frame(minHeight: 180)
            .accessibilityLabel("Note")
        }
      }
    }
    .navigationTitle(destination.note == nil ? "New taste note" : "Edit taste note")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save)
          .disabled(isBodyEmpty || isSaving)
      }
    }
    .alert("Couldn't save taste note", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  private func save() {
    let oldNote = destination.note
    let now = dateNow
    let authorID: UUID?
    if let oldNote {
      authorID = oldNote.authorID
    } else {
      authorID = UUID(uuidString: currentPersonIDString)
    }
    let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.subject
    let note = TasteNote(
      id: oldNote?.id ?? uuid(), householdID: oldNote?.householdID ?? destination.householdID,
      authorID: authorID, subject: subject, body: draft.body,
      createdAt: oldNote?.createdAt ?? now, updatedAt: now
    )
    isSaving = true
    Task {
      do {
        try await database.write { db in
          try TasteNote.upsert { TasteNote.Draft(note) }.execute(db)
        }
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}

private struct TasteNoteFormDraft {
  var subject: String
  var body: String
}

private struct StackedFormField<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption).foregroundStyle(.secondary)
        .accessibilityHidden(true)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}
