import BrightLightsSchema
import Foundation

public enum SourcePageMatcher {
  public static func source(
    for pageURL: URL,
    among sources: [Source],
    currentSource: Source? = nil
  ) -> Source? {
    let matches = sources.filter { $0.retiredAt == nil && host(pageURL.host, matches: $0) }
    if let currentSource, matches.contains(where: { $0.id == currentSource.id }) { return currentSource }
    return matches.sorted { lhs, rhs in
      let left = listingURL(lhs).map { sameHostAndPrefix(pageURL, $0) } ?? false
      let right = listingURL(rhs).map { sameHostAndPrefix(pageURL, $0) } ?? false
      if left != right { return left }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }.first
  }

  public static func isListingPage(_ pageURL: URL, for source: Source) -> Bool {
    guard let registered = listingURL(source), let pageHost = normalizedHost(pageURL.host),
      let sourceHost = normalizedHost(registered.host), pageHost == sourceHost else { return false }
    return normalizedPath(pageURL.path) == normalizedPath(registered.path)
  }

  public static func allowsPassiveCapture(_ source: Source) -> Bool {
    source.type == "venue" || source.type == "presenter"
  }

  private static func host(_ rawHost: String?, matches source: Source) -> Bool {
    guard let pageHost = normalizedHost(rawHost),
      let data = source.registeredHosts.data(using: .utf8),
      let registered = try? JSONDecoder().decode([String].self, from: data) else { return false }
    return registered.contains { value in
      guard let host = normalizedHost(value) else { return false }
      return pageHost == host || pageHost.hasSuffix(".\(host)")
    }
  }

  private static func listingURL(_ source: Source) -> URL? { URL(string: source.listingURL) }

  private static func sameHostAndPrefix(_ page: URL, _ listing: URL) -> Bool {
    guard normalizedHost(page.host) == normalizedHost(listing.host) else { return false }
    let path = normalizedPath(listing.path)
    return normalizedPath(page.path) == path || normalizedPath(page.path).hasPrefix(path == "/" ? "/" : "\(path)/")
  }

  private static func normalizedHost(_ value: String?) -> String? {
    value?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
  }

  private static func normalizedPath(_ value: String) -> String {
    let path = value.isEmpty ? "/" : value
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
