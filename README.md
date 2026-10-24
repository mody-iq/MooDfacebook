# MooDfacebook

Tweak for **Facebook** on **iOS 18.7 / arm64e / RootHide**.

## Features (v0.1.1)
- Hide **Sponsored / مموّل** posts
- Hide **Suggested for you / مقترح لك / People you may know**
- Optional hide **Stories** tray
- Optional hide **Reels** shelf labels
- Optional **Force Dark Mode**
- Preferences via PreferenceLoader plist (if Preferenceloader is installed)

## Defaults (all work out of the box)
| Key | Default |
|-----|---------|
| enabled | ON |
| hideAds | ON |
| hideSuggested | ON |
| hideStories | OFF |
| hideReelsShelf | OFF |
| forceDark | OFF |

Prefs file: `/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist`

## Build
GitHub Actions on `main` → artifact **MooDfacebook-deb**

## Install
1. Install `.deb`
2. Respring
3. Open Facebook

Author: **Mody**
