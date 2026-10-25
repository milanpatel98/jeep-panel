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
- CarPlay Apps tray: each app's own icon, from its App Store artwork (personal use only), fetched by
  `sh tools/fetch-app-icons.sh` into `Forx/Assets.xcassets`. Source: the `artworkUrl512` image (is1-ssl.mzstatic.com)
  that `https://itunes.apple.com/lookup?id=<id>` returns for YouTube Music (1017492454), Spotify (324684580),
  Apple Music (1108187390), Apple Maps (915056765), Podcasts (525463029), Google Maps (585027354) and
  Waze (323229106). Phone has no App Store page and keeps its SF Symbol; any icon not fetched does too.

© 2026 Milan Patel · MIT License
