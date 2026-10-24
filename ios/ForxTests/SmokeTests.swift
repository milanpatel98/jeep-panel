import Foundation
import Testing
@testable import Forx

struct SmokeTests {
    @Test func appBundleHasWebFolder() {
        #expect(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") != nil)
    }
}
