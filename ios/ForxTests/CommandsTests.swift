import Foundation
import Testing
@testable import Forx

struct CommandsTests {
    @Test func servicesFixtureEnablesExpected() {
        let services = enabledServices(fromJSON: Fixture.data("services"))
        #expect(supportedCommands(services: services) == [.lock, .unlock, .horn, .climateOn, .climateOff])
    }

    @Test func serviceMustBeCapableAndEnabled() {
        let json = Data("""
            [
              {"service": "RDL", "vehicleCapable": true, "serviceEnabled": true},
              {"service": "RDU", "vehicleCapable": false, "serviceEnabled": true},
              {"service": "HBLF", "vehicleCapable": true, "serviceEnabled": false},
              {"service": "ROLIGHTS", "vehicleCapable": "true", "serviceEnabled": "TRUE"},
              {"service": "REON", "vehicleCapable": 1, "serviceEnabled": 1},
              {"vehicleCapable": true, "serviceEnabled": true}
            ]
            """.utf8)
        let services = enabledServices(fromJSON: json)
        #expect(services == ["RDL", "ROLIGHTS"])
        #expect(supportedCommands(services: services) == [.lock, .lights])
    }

    @Test func routingMatchesCommandPy() {
        for cmd in JeepCommand.allCases {
            #expect(cmd.urlSuffix == "remote/")
            #expect(cmd.apiVersion == (cmd == .gate ? "v2" : "v1"))
        }
        #expect(JeepCommand.gate.rawValue == "ROLIFTGATEUNLOCK")
    }
}
