import Sharing

extension SharedKey where Self == AppStorageKey<String>.Default {
  static var currentPersonID: Self {
    Self[.appStorage("brightLightsCurrentPersonID"), default: ""]
  }
}

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

extension SharedKey where Self == AppStorageKey<String>.Default {
  static var checkerRegistrationError: Self {
    Self[.appStorage("brightLightsCheckerRegistrationError"), default: ""]
  }
}
