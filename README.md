# MooDfacebook

Jailbreak tweak for **Facebook** on **iOS 18.7 / arm64e / RootHide**.

## Features
- Hide Sponsored / paid posts (EN + AR labels)
- Hide suggested posts / people you may know
- Optional hide Stories tray
- Optional force Dark Mode
- Settings in **Settings → MooDfacebook** (PreferenceLoader)

## Package
- `com.modyiq.moodfacebook`
- Architecture: `iphoneos-arm64e`
- Scheme: RootHide (`THEOS_PACKAGE_SCHEME=roothide`)

## Build
CI builds on every push to `main` (macOS 15 + RootHide Theos).
Download the `.deb` from the Actions artifact **MooDfacebook-deb**.

## Install
1. Install the `.deb` (Sileo / Zebra / dpkg)
2. Respring
3. Open **Settings → MooDfacebook** and enable options
4. Relaunch Facebook

## Author
Mody
