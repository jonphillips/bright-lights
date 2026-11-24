import Foundation
import SQLiteData

@Table
public struct TasteNote: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var authorID: UUID?
  public var subject: String?
  public var body: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, householdID: UUID, authorID: UUID? = nil, subject: String? = nil, body: String,
    createdAt: Date = .now, updatedAt: Date = .now
  ) {
    self.id = id
    self.householdID = householdID
    self.authorID = authorID
    self.subject = subject
    self.body = body
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public func isEditable(by personID: UUID?) -> Bool {
    guard let authorID else { return true }
    return authorID == personID
  }

  public static func defaultSubject(for listing: Listing, performerNames: [String]) -> String {
    performerNames.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? listing.title
  }
}
