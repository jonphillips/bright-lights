import Dependencies
import BrightLightsSchema
import Foundation
import Observation
import SQLiteData

@MainActor
@Observable
final class SourceFixesModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now

  var errorMessage: String?
  var confirmationMessage: String?

  func setStartPage(_ url: String, for source: Source) {
    confirmationMessage = "Start page set for \(source.name)"
    Task {
      do {
        try await database.write { db in
          try Source.find(source.id).update { $0.startPageURL = #bind(url) }.execute(db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func resetStartPage(for source: Source) {
    confirmationMessage = "Start page reset for \(source.name)"
    Task {
      do {
        try await database.write { db in
          try Source.find(source.id).update { $0.startPageURL = #bind(nil as String?) }.execute(db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func flag(_ source: Source, note: String) {
    let note = String(note.prefix(200))
    let flaggedAt = now
    Task {
      do {
        try await database.write { db in
          try Source.find(source.id).update {
            $0.flaggedAt = #bind(flaggedAt)
            $0.flagNote = #bind(note.isEmpty ? nil : note)
          }.execute(db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func unflag(_ source: Source) {
    Task {
      do {
        try await database.write { db in
          try Source.find(source.id).update {
            $0.flaggedAt = #bind(nil as Date?)
            $0.flagNote = #bind(nil as String?)
          }.execute(db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }
}
