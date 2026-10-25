# MooDfacebook

A RootHide Theos tweak for **Facebook** (`com.facebook.Facebook`) on **iOS 18.x / arm64e**.

## Features

Every feature has its own switch in the in-app settings screen and is stored in
the `NSUserDefaults` suite `com.mody-iq.moodfacebook`.

| Feature | Default | Pref key |
|---------|---------|----------|
| Enable tweak (master switch) | ON | `enabled` |
| Remove ads / sponsored + suggested posts | ON | `hideAds` |
| Remove "People You May Know" | ON | `hidePYMK` |
| Hide the Reels carousel / shelf | ON | `hideReelsCarousel` |
| Confirm before a post is liked | ON | `confirmLike` |
| Download media on long press | ON | `downloadMedia` |
| Download Reels | ON | `downloadReels` |
| Hide the Reels UI overlay (player stays visible) | ON | `hideReelsOverlay` |
| Download Stories | ON | `downloadStories` |
| Watch Stories incognito (no seen receipt) | ON | `incognitoStories` |
| Open the share sheet after a video download | ON | `shareAfterDownload` |
| Floating settings button | ON | `showFloatingButton` |
| Verbose logging | OFF | `debug` |

All features are ON by default, so the tweak works with no preference bundle
installed. Image downloads always use the share sheet, because Facebook's
`Info.plist` has no photo-library usage description.

## Opening the settings screen

Two triggers, both deterministic:

1. **Floating gear button** - draggable, sits over the Facebook UI.
2. **Triple tap** anywhere on the screen, which works even when the button is
   hidden.

The previous long-press trigger was removed: Facebook installs its own
long-press recognisers on the feed and they win the gesture arena.

## Bug fixes

**Facebook was frozen: no scrolling or tapping while the floating button was
shown.** A transparent overlay window was swallowing every touch. UIKit asks the
*window* for the hit view, and `UIWindow` inherits `UIView`'s `hitTest:`, which
returns the window itself when no subview claims the point. So touches on the
button worked, but every other touch was delivered to the overlay window instead
of to Facebook, whose own window below never saw the event. The overlay is now an
`MDFPassthroughWindow` that returns `nil` for itself and for its root view, so
UIKit moves on to the window underneath. The same window is also kept out of the
key-window slot, so it cannot take keyboard focus from Facebook.

**Confirm like used to flash and disappear.** The alert is now presented on the
main thread from a `UIWindow` owned by the tweak, so a Facebook view-controller
transition cannot tear it down. An in-flight guard stops a second prompt from
dismissing the first, and the confirmed like is let through by matching its exact
target/action pair instead of a global flag.

**Sponsored posts stayed visible.** Cell matching now reads `text`,
`attributedText`, accessibility labels and accessibility identifiers from every
view in the subtree, not just `UILabel`, and only hides cells that live inside a
scrollable container so unrelated table/collection views are left alone.

**Reels showed a black screen.** The old code hid the first subtree that matched
the word "Like", which was usually the player container. A view is now hidden
only when it is a genuine control (a `UIControl`, or a view whose own
accessibility text says so) and its subtree contains no `AVPlayerLayer`. Close
and back controls are explicitly excluded so you can always leave the viewer.

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

CI: push to `main` and download the **MooDfacebook-deb** artifact from the
Actions run.

## Install

1. Install the `.deb` with your package manager.
2. Respring.
3. Open Facebook.

Author: **Mody**
