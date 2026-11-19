import Sharing

extension SharedKey where Self == AppStorageKey<String>.Default {
  static var checkerDeviceID: Self {
    Self[.appStorage("brightLightsCheckerDeviceID"), default: ""]
  }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
  static var checkerEnabled: Self {
    Self[.appStorage("brightLightsCheckerEnabled"), default: false]
  }
}
