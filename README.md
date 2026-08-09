# GroceryApp

This repository contains the GroceryApp reference application and its local Swift packages.

## Local signing setup

Apple signing is configured through an ignored, per-developer xcconfig file. Your team identifier and bundle identifier stay local and are not committed to Git.

1. Copy the template:

   ```sh
   cp Config/App.local.xcconfig.example Config/App.local.xcconfig
   ```

2. Edit `Config/App.local.xcconfig` and replace the placeholders:

   ```xcconfig
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = your.bundle.identifier
   ```

3. Open `GroceryApp.xcodeproj` in Xcode and build the `GroceryApp` target.

`Config/App.xcconfig` is committed and provides shared defaults. It includes `App.local.xcconfig` when that file exists. The local file is listed in `.gitignore`, so personal signing values do not appear in project-file diffs or commits.

The app target's Debug and Release configurations already use the shared xcconfig. Do not reselect the team in Xcode's Signing & Capabilities panel unless you intend to change the project configuration; edit `Config/App.local.xcconfig` instead.

To verify the effective local settings from the command line:

```sh
xcodebuild -project GroceryApp.xcodeproj \
  -target GroceryApp \
  -showBuildSettings \
  -disableAutomaticPackageResolution \
  | grep -E 'DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE'
```

## Project layout

- `GroceryApp/` — application source
- `GroceryAppTests/` — application tests
- `Packages/` — local Swift packages
- `Config/App.xcconfig` — committed shared build settings
- `Config/App.local.xcconfig` — ignored local signing settings
