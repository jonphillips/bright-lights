import BrightLightsSchema
import Foundation
import Observation

/// App-level selection and cross-screen browser handoff.
@MainActor
@Observable
final class AppRouter {
  var selection: AppScreen? = .comingUp

  @ObservationIgnored private let browserModel: BrowserModel

  init(browserModel: BrowserModel) {
    self.browserModel = browserModel
  }

  func capture(_ source: Source) {
    selection = .capture
    browserModel.open(source)
  }

  func capture(_ url: URL) {
    selection = .capture
    browserModel.open(url)
  }
}
