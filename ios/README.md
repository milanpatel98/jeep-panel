# Forx (iPhone app)

Personal iPhone app that wraps the Jeep Panel web app. The Xcode project is generated from `project.yml` with XcodeGen.

First time only: `brew install xcodegen`

```bash
cd ~/Developer/jeep-panel/ios && git pull && xcodegen && open Forx.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities (first run only), choose an iPhone simulator, and press Run. Tests: Cmd+U.

## Credits

- [py-uconnect](https://github.com/hass-uconnect/py-uconnect) (Apache-2.0): the Uconnect client is a Swift port of it.
- [three.js](https://threejs.org) (MIT): the 3D Jeep.
- [Phosphor Icons](https://phosphoricons.com) (MIT): the icons.

© 2026 Milan Patel · MIT License
