# Now

Single-column todo app for iPhone and Mac. Shows the 3 things that need you next. See [SCOPE.md](SCOPE.md).

## Layout

- `NowCore/`: Swift package with ranking, working hours, notification planning, quick dates, and due labels. No UI, fully tested.
- `App/`: SwiftUI app shared by the iOS and macOS targets (SwiftData models, views, services).
- `Resources/`: asset catalog and privacy manifest.
- `Config/`: entitlements and the iOS Info.plist additions.
- `project.yml`: XcodeGen spec that generates `Now.xcodeproj`.

## Setup

1. Install Xcode from the App Store, then `sudo xcode-select -s /Applications/Xcode.app`.
2. Install XcodeGen: `brew install xcodegen`.
3. Set `DEVELOPMENT_TEAM` in `project.yml` to your team ID. Change `com.nikhilkapadia.now` and `iCloud.com.nikhilkapadia.now` if you want different identifiers.
4. `xcodegen generate && open Now.xcodeproj`
5. In the target's Signing & Capabilities, confirm the iCloud container exists (Xcode offers to create it).

Without a team or iCloud container the app still runs, with local storage only.

## Tests

```sh
NowCore/test.sh
```

`test.sh` works with only the Command Line Tools installed. With Xcode, `swift test` in `NowCore/` also works.
