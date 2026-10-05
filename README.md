<h1 align="center">Pumperly for iOS</h1>

<p align="center">
  <a href="https://github.com/GeiserX/pumperly-ios/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/GeiserX/pumperly-ios/ci.yml?style=flat-square&label=CI" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/GeiserX/pumperly-ios?style=flat-square" alt="License"></a>
</p>

Pumperly for iOS is the iPhone app for [Pumperly](https://pumperly.com), the open-source fuel and EV route planner that finds the cheapest place to refuel along your route. It shows the web app in a native SwiftUI shell and adds a "Cheapest nearby" home screen widget with live prices for your fuel. The first builds go to TestFlight, then to the App Store.

<p align="center">
  <img src="docs/images/screenshot-route.png" alt="Route planner in the app" width="240">
  <img src="docs/images/widget-medium.png" alt="Cheapest nearby widget, medium" width="300">
  <img src="docs/images/widget-small.png" alt="Cheapest nearby widget, small" width="150">
</p>

## Features

- The full Pumperly route planner, with fuel and EV prices along the route, from the live site.
- A "Cheapest nearby" widget in small and medium sizes: the cheapest stations around you for your fuel, refreshed about hourly. Tapping a station opens its page in the app.
- One native setting, the widget's fuel, asked once on first launch and reachable from the widget or by holding the app icon.
- Native location: the site and the widget share one iOS permission, and only pumperly.com pages can read it.
- Only `https://pumperly.com` loads inside the app; every other link opens in Safari or the app that owns it.
- Universal links: pumperly.com links open in the app once it is installed.
- Offline, certificate and page error screens with retry, pull to refresh, a progress bar and dark mode that follows the system.
- English and Spanish.

<p align="center">
  <img src="docs/images/screenshot-settings.png" alt="Widget fuel setting" width="240">
  <img src="docs/images/screenshot-offline.png" alt="Offline screen" width="240">
</p>

## Quick start

You need Xcode 16 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml` and is not committed.

```bash
brew install xcodegen
xcodegen generate
open Pumperly.xcodeproj
```

Run the `Pumperly` scheme on an iPhone simulator. `xcodebuild test -scheme Pumperly -destination 'platform=iOS Simulator,name=iPhone 17'` runs the unit and UI tests, as CI does on every pull request.

## Release

`project.yml` holds the version (`MARKETING_VERSION`) and the build number (`CURRENT_PROJECT_VERSION`); bump the build number for every upload. Pushing a tag `vX.Y.Z` that matches the version runs `.github/workflows/release.yml`, which archives with manual signing and uploads the build to TestFlight. It needs these repository secrets:

| Secret | Contents |
|---|---|
| `APPSTORE_ISSUER_ID` | App Store Connect API issuer id |
| `APPSTORE_KEY_ID` | App Store Connect API key id |
| `APPSTORE_PRIVATE_KEY` | The key's `.p8` file, as text |
| `DIST_CERTIFICATE_P12` | Apple Distribution certificate and private key, `.p12` in base64 |
| `DIST_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `PROFILE_APP` | App Store profile "Pumperly App Store" for `com.pumperly.app`, base64 |
| `PROFILE_WIDGET` | App Store profile "Pumperly Widget App Store" for `com.pumperly.app.widget`, base64 |

Both profiles need the App Group `group.com.pumperly.app`; the app's profile also needs Associated Domains.

## Related projects

[Pumperly](https://github.com/GeiserX/Pumperly) (the web app), [Pumperly for Android](https://github.com/GeiserX/Pumperly-android), [pumperly-mcp](https://github.com/GeiserX/pumperly-mcp), [pumperly-ha](https://github.com/GeiserX/pumperly-ha).

## License

[GPL-3.0-only](LICENSE)
