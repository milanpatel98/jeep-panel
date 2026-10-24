import Foundation
import Testing
@testable import Forx

struct SmokeTests {
    @Test func appBundleHasWebFolder() {
        #expect(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") != nil)
    }

    @Test func carPlaySceneDeclared() {
        let manifest = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
        let configs = manifest?["UISceneConfigurations"] as? [String: Any]
        let roles = configs?["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]]
        let name = roles?.first?["UISceneDelegateClassName"] as? String
        #expect(name?.hasSuffix("CarPlaySceneDelegate") == true)
    }
}
