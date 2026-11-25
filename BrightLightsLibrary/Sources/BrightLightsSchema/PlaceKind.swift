import SQLiteData

public enum PlaceKind: String, QueryBindable, CaseIterable, Sendable {
  case food
  case drink
  case coffee
  case park
  case shop
  case sight
  case activity
  case other
}
