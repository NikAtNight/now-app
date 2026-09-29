# Podium

Single-column todo app for iPhone and Mac. Shows the 3 things that need you next. See [SCOPE.md](SCOPE.md).

## Layout

- `NowCore/`: Swift package with ranking, working hours, notification planning, quick dates, and due labels. No UI, fully tested.
- `App/`: SwiftUI app shared by the iOS and macOS targets (SwiftData models, views, services). `App/Mac/` is Mac-only (quick add).
- `Shared/`: code compiled into both the app and the widget extension (shared store, priority style, the complete-task intent, Live Activity attributes).
- `Widgets/`: the WidgetKit extension (`PodiumWidgets-iOS`, `PodiumWidgets-macOS`): the "Now" widget and the timer Live Activity.
- `scripts/app-icon.swift`: draws the app icon PNGs.
- `Resources/`: asset catalog and privacy manifest.
- `Config/`: entitlements and the iOS Info.plist additions.
- `project.yml`: XcodeGen spec that generates `Podium.xcodeproj`.

## Setup

1. Install Xcode from the App Store, then `sudo xcode-select -s /Applications/Xcode.app`.
2. Install XcodeGen: `brew install xcodegen`.
3. `xcodegen generate && open Podium.xcodeproj`. The team (`2TG5HP8NSV`), bundle IDs `com.talix.now` and `com.talix.now.widgets`, the container `iCloud.com.talix.now`, and the App Group (`group.com.talix.now` on iOS, `2TG5HP8NSV.com.talix.now` on Mac) are already set in `project.yml` and `Config/`.
4. From the command line, pass `-allowProvisioningUpdates` to `xcodebuild` so automatic signing can fetch profiles.

Without a team or iCloud container the app still runs, with local storage only.

## Tests

```sh
NowCore/test.sh
```

`test.sh` works with only the Command Line Tools installed. With Xcode, `swift test` in `NowCore/` also works.
