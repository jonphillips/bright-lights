import BrightLightsSchema
import Testing

@Suite("Build stamp")
struct BuildStampTests {
  @Test func readsCompleteStamp() {
    let stamp = BuildStamp.from(infoDictionary: [
      "BLBuild": "53e94bd",
      "BLDirty": "false",
      "BLBuiltAt": "2026-11-20T14:28:00Z"
    ])

    #expect(stamp == BuildStamp(build: "53e94bd", dirty: false, builtAt: "2026-11-20T14:28:00Z"))
  }

  @Test func incompleteStampIsUnknown() {
    #expect(BuildStamp.from(infoDictionary: [:]) == .unknown)
    #expect(BuildStamp.from(infoDictionary: ["BLBuild": "53e94bd", "BLDirty": "false"]) == .unknown)
    #expect(BuildStamp.from(infoDictionary: [
      "BLBuild": "53e94bd", "BLDirty": "sometimes", "BLBuiltAt": "2026-11-20T14:28:00Z"
    ]) == .unknown)
  }
}
