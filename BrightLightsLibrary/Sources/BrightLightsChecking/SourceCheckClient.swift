import Dependencies
import Foundation
import WebExtractorKit

public struct FetchedPage: Sendable, Equatable {
  public var document: String
  public var statusCode: Int
  public var effectiveURL: URL
  public var contentType: String?

  public init(document: String, statusCode: Int, effectiveURL: URL, contentType: String? = nil) {
    self.document = document
    self.statusCode = statusCode
    self.effectiveURL = effectiveURL
    self.contentType = contentType
  }
}

public struct SourceCheckClient: Sendable {
  public var fetch: @Sendable (URL, Bool) async throws -> FetchedPage
  public var wait: @Sendable (Duration) async throws -> Void

  public init(
    fetch: @escaping @Sendable (URL, Bool) async throws -> FetchedPage,
    wait: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.fetch = fetch
    self.wait = wait
  }

  public static let live = SourceCheckClient(
    fetch: { url, rendered in
      if rendered {
        guard let document = await RenderedDOMFetcher.renderedDocument(of: url) else {
          throw SourceCheckError.fetchFailed("rendered page could not be loaded")
        }
        return FetchedPage(document: document.html, statusCode: 200, effectiveURL: document.effectiveURL, contentType: "text/html")
      }
      var request = URLRequest(url: url)
      request.setValue("BrightLights/0.1.0 (personal, non-commercial)", forHTTPHeaderField: "User-Agent")
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      let session = URLSession(configuration: configuration)
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, let finalURL = http.url else {
        throw SourceCheckError.fetchFailed("not an HTTP response")
      }
      return FetchedPage(
        document: String(decoding: data, as: UTF8.self), statusCode: http.statusCode,
        effectiveURL: finalURL, contentType: http.value(forHTTPHeaderField: "Content-Type")
      )
    },
    wait: { try await Task.sleep(for: $0) }
  )
}

extension SourceCheckClient: DependencyKey {
  public static let liveValue = SourceCheckClient.live
  public static let testValue = SourceCheckClient(
    fetch: { _, _ in throw SourceCheckError.fetchFailed("No test fetch configured") },
    wait: { _ in }
  )
}

extension DependencyValues {
  public var sourceCheckClient: SourceCheckClient {
    get { self[SourceCheckClient.self] }
    set { self[SourceCheckClient.self] = newValue }
  }
}

public enum SourceCheckError: Error, LocalizedError, Sendable {
  case fetchFailed(String)
  case disallowed(URL)
  case challenge(String)
  case noModelKey
  case noListings(previousCount: Int? = nil)

  public var errorDescription: String? {
    switch self {
    case let .fetchFailed(note), let .challenge(note): note
    case let .disallowed(url): "robots.txt disallows \(url.path)"
    case .noModelKey: "no model key"
    case let .noListings(previousCount):
      previousCount.map { "returned no listings (was \($0))" } ?? "returned no listings"
    }
  }
}
