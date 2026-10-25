# MooDfacebook

A RootHide Theos tweak for **Facebook** (`com.facebook.Facebook`) on **iOS 18.x / arm64e**.

## Features

| # | Feature | Default | Pref key |
|---|---------|---------|----------|
| 1 | Remove ads / sponsored + suggested posts | ON | `hideAds` |
| 2 | Remove "People you may know" | ON | `hidePYMK` |
| 3 | Hide the Reels carousel / shelf | ON | `hideReelsCarousel` |
| 4 | Confirm before a post is liked | ON | `confirmLike` |
| 5 | Download media on long press | ON | `downloadMedia` |
| 6 | Download Reels + hide the Reels overlay | ON | `downloadReels`, `hideReelsOverlay` |
| 7 | Download Stories + watch incognito (no seen receipt) | ON | `downloadStories`, `incognitoStories` |

Every feature is ON by default, so the tweak works with no preference bundle installed.
The master switch is `enabled`. Set `debug` to `YES` for `[MooDfacebook]` logging.

Preferences live in the `NSUserDefaults` suite `com.mody-iq.moodfacebook`.

## Layout

```
Makefile                          # roothide scheme, arm64e, iOS 15.0 deployment target
control                           # package metadata (iphoneos-arm64e)
MooDfacebook.plist                # MobileLoader filter for com.facebook.Facebook
Tweak.x                           # tweak source
.github/workflows/build.yml       # CI: builds the .deb and uploads it as an artifact
```

## Build

Local:

```sh
export THEOS=/path/to/theos          # roothide/theos fork
make package FINALPACKAGE=1
```

CI: push to `main` and download the **MooDfacebook-deb** artifact from the Actions run.

## Install

1. Install the `.deb` with your package manager.
2. Respring.
3. Open Facebook.

Author: **Mody**

