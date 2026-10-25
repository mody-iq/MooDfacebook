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
| Download button on media | ON | `showDownloadButton` |
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

**Sponsored posts stayed visible.** Matching now looks at the cell header only
(the top three levels), plus accessibility identifiers and class names, so an
ordinary post whose body merely mentions "sponsored" is not hidden while a real
ad is. With debug logging on, the tweak dumps each cell's strings so the markers
can be tuned against your exact Facebook build.

**The feed disappeared at random (Reels carousel).** Facebook recycles cell
objects while you scroll. The old code only ever set `hidden = YES` and never
cleared it, so once a sponsored post scrolled past, every later post that reused
that cell object stayed invisible — which is why the feed sometimes vanished and
sometimes did nothing. The decision is now symmetric: it is recomputed on every
layout pass and assigned, so a recycled cell is always restored. The Reels shelf
is matched by class name, because an ordinary video post also contains the word
"reels" in its body.

**Downloads did nothing.** Facebook serves video over HLS, so the captured URL is
usually an `.m3u8` playlist. Downloading it with `NSURLSession` produced a text
file, not a video. Playlists are now parsed, every segment is fetched in
parallel, and the segments are concatenated into a playable `.ts` file. The media
URL is captured from `AVPlayerItem` as well as `AVPlayer`, and resolved through
`AVComposition` track segments when the asset has no URL of its own.

**Hide Reels overlay and Incognito Stories did nothing.** The overlay pass ran
only four times within 2.5 seconds, so controls created later (a new Reel after a
swipe) were never hidden; a watcher now re-applies the rule while the viewer is
on screen. The incognito scan had two bugs: the class-name test was
case-sensitive (`"Story"` never matched `"story"`), and it ran once at load time,
before Facebook had loaded its Story classes. It is now case-insensitive, skips
getters, and is retried several times after launch.

**Reels showed a black screen.** The old code hid the first subtree that matched
the word "Like", which was usually the player container. A view is now hidden
only when it is a genuine control (a `UIControl`, or a view whose own
accessibility text says so) and its subtree contains no `AVPlayerLayer`. Close
and back controls are explicitly excluded so you can always leave the viewer.

## Download button

A small download icon sits on media so you do not have to rely on a long press,
which Facebook's own gesture recognisers frequently win:

* Reels and videos: left side, directly above the Like button. It follows the
  Like button on every layout pass, so it survives a rebuilt action rail.
* Stories: top-right corner.
* Feed photos and videos: on the media area of the cell.

Tapping it downloads immediately (or opens the share sheet, per the setting). The
button is excluded from the overlay-hiding pass, so hiding the Reels UI never
hides it. Turn it off with the `showDownloadButton` switch.

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
