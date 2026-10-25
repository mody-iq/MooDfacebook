// MooDfacebook — RootHide (roothide) tweak for Facebook (com.facebook.Facebook)
// iOS 18.x / arm64e.
//
// Features (each has its own UISwitch in the in-app settings screen)
//   1. Remove ads / sponsored + suggested posts        hideAds
//   2. Remove "People you may know" / suggested        hidePYMK
//   3. Hide the Reels carousel / shelf                 hideReelsCarousel
//   4. Confirm before a post is liked                  confirmLike
//   5. Download media on long press                    downloadMedia
//   6. Download Reels                                  downloadReels
//   7. Hide the Reels UI overlay (player stays intact) hideReelsOverlay
//   8. Download Stories                                downloadStories
//   9. Watch Stories incognito (no seen receipt)       incognitoStories
//  10. Copy link instead of opening the share sheet    shareAfterDownload
//      (video downloads only; image downloads always use the share sheet)
//  11. Floating gear button                            showFloatingButton
//  12. Download button on media                        showDownloadButton
//  13. Master switch                                   enabled
//  14. Verbose logging                                 debug
//
// Preferences live in the NSUserDefaults suite com.mody-iq.moodfacebook, so the
// tweak keeps working (with safe defaults) even if no preference bundle is
// installed. The in-app settings screen writes to the same suite.
//
// Design notes
//   * Every UIKit touch happens on the main thread. The settings screen and the
//     confirm-like alert are presented from dedicated UIWindows so a Facebook
//     view-controller transition can never tear them down mid-animation.
//   * The Reels fix hides *only* control widgets. A widget is a control only if
//     it is a UIControl, or a view whose accessibility label matches a control
//     word AND which has no AVPlayerLayer anywhere in its subtree. That second
//     condition is what stops the video player from being hidden (black screen).
//   * The settings screen is reachable through a draggable floating button and a
//     triple tap anywhere, because the previous long-press trigger was
//     unreliable inside Facebook's own gesture stack.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Constants

#define MDF_VERSION @"2.1.0"

static NSString *const kMDFSuite = @"com.mody-iq.moodfacebook";
static NSString *const kMDFLongPressName = @"mdf.longpress";
static NSString *const kMDFDownloadButtonIdentifier = @"mdf.download.button";
static NSString *const kMDFScopeReels = @"reels";
static NSString *const kMDFScopeStories = @"stories";
static NSString *const kMDFScopeMedia = @"media";

#pragma mark - Preferences

// One cached suite instance: NSUserDefaults is thread-safe, and the hooks read
// preferences on hot paths (every cell layout, every viewDidAppear).
static NSUserDefaults *MDFSuiteDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:kMDFSuite]; });
    return defaults;
}

static BOOL MDFPref(NSString *key, BOOL fallback) {
    NSNumber *value = [MDFSuiteDefaults() objectForKey:key];
    return value ? value.boolValue : fallback;
}

static void MDFSetPref(NSString *key, BOOL value) {
    [MDFSuiteDefaults() setBool:value forKey:key];
}

static BOOL MDFDebug(void) { return MDFPref(@"debug", NO); }

#define MDFLog(fmt, ...) do { if (MDFDebug()) NSLog(@"[MooDfacebook] " fmt, ##__VA_ARGS__); } while (0)

// Registered once so every switch starts from the same default the README
// documents, and so the settings screen can read current values.
static void MDFRegisterDefaults(void) {
    NSDictionary *defaults = @{
        @"enabled": @YES,
        @"hideAds": @YES,
        @"hidePYMK": @YES,
        @"hideReelsCarousel": @YES,
        @"confirmLike": @YES,
        @"downloadMedia": @YES,
        @"downloadReels": @YES,
        @"hideReelsOverlay": @YES,
        @"downloadStories": @YES,
        @"incognitoStories": @YES,
        @"shareAfterDownload": @YES,
        @"showFloatingButton": @YES,
        @"showDownloadButton": @YES,
        @"debug": @NO,
    };
    NSUserDefaults *suite = MDFSuiteDefaults();
    for (NSString *key in defaults) {
        if (![suite objectForKey:key]) [suite setObject:defaults[key] forKey:key];
    }
}

#pragma mark - Localisation-aware marker tables
//
// Markers are matched case-insensitively against a view's label, accessibility
// label and accessibility identifier. English + Arabic + the main European
// locales are covered; extend the arrays as needed.

static NSArray<NSString *> *MDFAdMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"sponsored", @"مموّل", @"ممول", @"sponsorisé", @"patrocinado",
                    @"sponsorizzato", @"anzeige", @"publicidad", @"реклама", @"gesponsert",
                    @"sponsrad", @"sponsorerad", @"sponsored post"];
    });
    return markers;
}

static NSArray<NSString *> *MDFSuggestedMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"suggested for you", @"مقترح لك", @"suggéré pour vous",
                    @"sugerido para ti", @"suggerito per te", @"vorgeschlagen für dich",
                    @"suggestions"];
    });
    return markers;
}

static NSArray<NSString *> *MDFPYMKMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"people you may know", @"أشخاص قد تعرفهم", @"personnes que vous",
                    @"personas que quizá conozcas", @"persone che potresti conoscere",
                    @"personen, die du kennen könntest", @"mutual friends",
                    @"أصدقاء مشتركون"];
    });
    return markers;
}

static NSArray<NSString *> *MDFReelsMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"reels and short videos", @"مقاطع ريلز", @"reels et vidéos courtes",
                    @"reels y videos cortos", @"reels e video brevi", @"reels und kurzvideos"];
    });
    return markers;
}

// Accessibility identifiers Facebook puts on sponsored / suggested cells. These
// are far more stable than visible text and are matched against the whole cell.
static NSArray<NSString *> *MDFAdIdentifierMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"sponsored", @"sponsor", @"paid_partnership", @"suggested_post",
                    @"suggested_for_you", @"suggestedfor", @"promoted", @"ad_", @"_ad",
                    @"ads_", @"_ads", @"branded_content", @"boosted"];
    });
    return markers;
}

// Class names that mark a cell (or a wrapper) as an ad container.
static NSArray<NSString *> *MDFAdClassMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"sponsored", @"sponsorcontent", @"sponsoredcontent", @"paidpartnership",
                    @"brandedcontent", @"promotedpost", @"adsstory", @"adspost"];
    });
    return markers;
}

// Class names that mark the feed's Reels shelf / carousel. Deliberately narrow:
// matching the word "reel" anywhere would also catch the Reels viewer and
// ordinary video posts.
static NSArray<NSString *> *MDFReelsShelfClassMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"reelsshelf", @"reelcarousel", @"reelscarousel", @"reelstray",
                    @"reelunit", @"reelsunit", @"reelsfeedunit", @"reelsattachment",
                    @"reelsvideoshelf", @"shortvideosshelf", @"reelsshortvideos"];
    });
    return markers;
}

// YES if the view or any ancestor's class name matches one of the markers.
static BOOL MDFViewMatchesClassNames(UIView *view, NSArray<NSString *> *markers) {
    UIView *current = view;
    NSUInteger hops = 0;
    while (current && hops < 6) {
        NSString *className = NSStringFromClass([current class]).lowercaseString;
        for (NSString *marker in markers) {
            if ([className containsString:marker]) return YES;
        }
        current = current.superview;
        hops++;
    }
    return NO;
}

// Words that appear on Reels/Stories control widgets. Only used to classify a
// view as a control when the view is not itself a UIControl.
static NSArray<NSString *> *MDFOverlayControlMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"like", @"comment", @"share", @"send", @"save", @"more options",
                    @"music", @"audio", @"remix", @"follow", @"view profile",
                    @"إعجاب", @"تعليق", @"مشاركة", @"إرسال", @"حفظ", @"مزيد من الخيارات",
                    @"متابعة"];
    });
    return markers;
}

#pragma mark - View helpers

static BOOL MDFStringMatchesMarkers(NSString *text, NSArray<NSString *> *markers) {
    if (!text.length) return NO;
    NSString *haystack = text.lowercaseString;
    for (NSString *marker in markers) {
        if ([haystack containsString:marker.lowercaseString]) return YES;
    }
    return NO;
}

// Collects every piece of text a subtree can expose. Facebook renders labels
// through its own text views as well as UILabel, so `text` and `attributedText`
// are read from any responder, not only UILabel.
static void MDFCollectText(UIView *view, NSMutableArray<NSString *> *out, NSUInteger depth) {
    if (!view || depth > 12 || out.count > 400) return;
    if (view.accessibilityLabel.length) [out addObject:view.accessibilityLabel];
    if (view.accessibilityIdentifier.length) [out addObject:view.accessibilityIdentifier];
    if ([view respondsToSelector:@selector(text)]) {
        id text = [view performSelector:@selector(text)];
        if ([text isKindOfClass:[NSString class]] && [text length]) [out addObject:text];
    }
    if ([view respondsToSelector:@selector(attributedText)]) {
        NSAttributedString *attributed = [view performSelector:@selector(attributedText)];
        if (attributed.string.length) [out addObject:attributed.string];
    }
    for (UIView *sub in view.subviews) MDFCollectText(sub, out, depth + 1);
}

// A full-subtree text scan is right for a whole feed cell, but wrong for a
// single header: a post whose *body* happens to contain the word "sponsored"
// would be hidden. For headers we only look at the top few levels, which is
// where Facebook renders the author line and the "Sponsored" badge.
static BOOL MDFCollectTextShallow(UIView *view, NSMutableArray<NSString *> *out,
                                  NSUInteger depth, NSUInteger maxDepth) {
    if (!view || depth > maxDepth) return NO;
    if (out.count > 60) return YES;
    if (view.accessibilityLabel.length) [out addObject:view.accessibilityLabel];
    if (view.accessibilityIdentifier.length) [out addObject:view.accessibilityIdentifier];
    if ([view respondsToSelector:@selector(text)]) {
        id text = [view performSelector:@selector(text)];
        if ([text isKindOfClass:[NSString class]] && [text length]) [out addObject:text];
    }
    for (UIView *sub in view.subviews) {
        if (MDFCollectTextShallow(sub, out, depth + 1, maxDepth)) return YES;
    }
    return NO;
}

static BOOL MDFViewShallowMatchesMarkers(UIView *view, NSArray<NSString *> *markers,
                                         NSUInteger maxDepth) {
    if (!view) return NO;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    MDFCollectTextShallow(view, texts, 0, maxDepth);
    for (NSString *text in texts) {
        if (MDFStringMatchesMarkers(text, markers)) return YES;
    }
    return NO;
}

// When debug logging is on, dump the strings a feed cell exposes. This is what
// lets the markers be tuned against a real Facebook build without guessing:
// the log shows the exact labels, accessibility labels and class names.
static void MDFDumpCellText(UIView *cell) {
    if (!MDFDebug()) return;
    static NSUInteger dumped = 0;
    if (dumped >= 40) return; // enough to tune the markers; avoid flooding
    dumped++;

    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    MDFCollectText(cell, texts, 0);
    NSMutableArray<NSString *> *unique = [NSMutableArray array];
    for (NSString *text in texts) {
        if (![unique containsObject:text]) [unique addObject:text];
    }
    MDFLog(@"cell %@ text=%@", NSStringFromClass([cell class]), [unique componentsJoinedByString:@" | "]);
}

// Facebook marks sponsored cells with a stable accessibility identifier far
// more often than with a visible label, so identifiers are matched on their own.
static void MDFCollectIdentifiers(UIView *view, NSMutableArray<NSString *> *out, NSUInteger depth) {
    if (!view || depth > 12 || out.count > 200) return;
    if (view.accessibilityIdentifier.length) [out addObject:view.accessibilityIdentifier];
    for (UIView *sub in view.subviews) MDFCollectIdentifiers(sub, out, depth + 1);
}

static BOOL MDFViewIdentifierMatchesMarkers(UIView *view, NSArray<NSString *> *markers) {
    if (!view) return NO;
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    MDFCollectIdentifiers(view, identifiers, 0);
    for (NSString *identifier in identifiers) {
        if (MDFStringMatchesMarkers(identifier, markers)) return YES;
    }
    return NO;
}

// YES if a view matches the markers *directly* (its own label / a11y strings),
// which avoids walking the whole subtree for every ancestor we test.
static BOOL MDFViewSelfMatchesMarkers(UIView *view, NSArray<NSString *> *markers) {
    if (!view) return NO;
    if (MDFStringMatchesMarkers(view.accessibilityLabel, markers)) return YES;
    if (MDFStringMatchesMarkers(view.accessibilityIdentifier, markers)) return YES;
    if ([view respondsToSelector:@selector(text)]) {
        id text = [view performSelector:@selector(text)];
        if ([text isKindOfClass:[NSString class]] && MDFStringMatchesMarkers(text, markers)) return YES;
    }
    return NO;
}

static BOOL MDFViewContainsPlayer(UIView *view) {
    if (!view) return NO;
    if ([view.layer isKindOfClass:[AVPlayerLayer class]]) return YES;
    for (UIView *sub in view.subviews) {
        if (MDFViewContainsPlayer(sub)) return YES;
    }
    return NO;
}

static AVPlayer *MDFPlayerInView(UIView *view) {
    if (!view) return nil;
    if ([view.layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *player = ((AVPlayerLayer *)view.layer).player;
        if (player) return player;
    }
    for (UIView *sub in view.subviews) {
        AVPlayer *player = MDFPlayerInView(sub);
        if (player) return player;
    }
    return nil;
}

// Resolves the media URL for a player. Facebook plays HLS, and the asset is
// frequently an AVComposition whose tracks carry the real URL, so all of these
// sources are tried in order of reliability.
static NSURL *MDFResolveAssetURL(AVAsset *asset) {
    if (!asset) return nil;
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        NSURL *url = ((AVURLAsset *)asset).URL;
        if (url) return url;
    }
    // A composition has no URL of its own; look at the URL assets in its tracks.
    if ([asset isKindOfClass:[AVComposition class]]) {
        for (AVCompositionTrack *track in ((AVComposition *)asset).tracks) {
            for (AVCompositionTrackSegment *segment in track.segments) {
                if (segment.sourceURL) return segment.sourceURL;
            }
        }
    }
    return nil;
}

static NSURL *MDFVideoURLInView(UIView *view) {
    AVPlayer *player = MDFPlayerInView(view);
    if (!player) return nil;
    // Prefer the URL we recorded when the item was replaced: the item's asset is
    // often a composition with no resolvable URL.
    NSURL *recorded = objc_getAssociatedObject(player, "mdf.mediaURL");
    if ([recorded isKindOfClass:[NSURL class]]) return recorded;
    AVPlayerItem *item = player.currentItem;
    NSURL *fromItem = objc_getAssociatedObject(item, "mdf.mediaURL");
    if ([fromItem isKindOfClass:[NSURL class]]) return fromItem;
    return MDFResolveAssetURL(item.asset);
}

static UIImage *MDFImageInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage *image = ((UIImageView *)view).image;
        if (image) return image;
    }
    for (UIView *sub in view.subviews) {
        UIImage *image = MDFImageInView(sub);
        if (image) return image;
    }
    return nil;
}

// Walk up from a cell to the scrollable container (feed / shelf). Any
// UIScrollView subclass qualifies, so a custom Facebook scroll subclass still
// works; pickers and other non-scrolling containers do not.
static UIView *MDFFeedContainerAncestor(UIView *view) {
    UIView *current = view.superview;
    while (current) {
        if ([current isKindOfClass:[UIScrollView class]]) return current;
        current = current.superview;
    }
    return nil;
}

#pragma mark - Forward declarations

@class MDFFloatingRootViewController;
static UIViewController *MDFFloatingRootViewControllerInstance(void);
static void MDFSetupUI(void);
static void MDFPresentSettings(void);
static void MDFPresentShare(NSURL *fileURL);
static void MDFToast(NSString *message);
static void MDFHandleViewControllerAppear(UIViewController *controller);
static void MDFInstallLongPress(UIView *host, NSString *scope);

#pragma mark - Overlay hiding (Reels / Stories) — the black-screen fix
//
// The old code called a recursive "does this subtree contain the word Like?"
// match and hid the *whole* matched subtree. Facebook's Reels player is wrapped
// in a container whose subtree also holds the action rail, so the first match
// was the player container itself — hiding it produced a black screen.
//
// The rule below only ever hides a genuine control widget, and refuses to hide
// anything that owns an AVPlayerLayer:
//   * a UIControl (button / toggle) is a control, unless it holds the player;
//   * any other view is a control only when its *own* accessibility text says so
//     AND its subtree contains no AVPlayerLayer.
// Containers that merely hold a player are therefore left untouched.

static BOOL MDFViewIsOverlayExcluded(UIView *view);

static BOOL MDFViewIsControlWidget(UIView *view) {
    if (!view) return NO;
    if (MDFViewContainsPlayer(view)) return NO;
    if (MDFViewIsOverlayExcluded(view)) return NO;
    if ([view isKindOfClass:[UIControl class]]) return YES;
    if (MDFViewSelfMatchesMarkers(view, MDFOverlayControlMarkers())) return YES;
    return NO;
}

// Navigation controls are deliberately left visible: hiding the close button
// would trap the user inside the Reels viewer.
static NSArray<NSString *> *MDFOverlayExclusionMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"close", @"back", @"dismiss", @"cancel", @"exit", @"done",
                    @"إغلاق", @"رجوع", @"إلغاء", @"خروج", @"تم"];
    });
    return markers;
}

static BOOL MDFViewIsOverlayExcluded(UIView *view) {
    // The tweak's own download button is a UIControl, so the control-widget
    // pass would otherwise hide the very button we just added.
    if ([view.accessibilityIdentifier isEqualToString:kMDFDownloadButtonIdentifier]) return YES;
    if (MDFStringMatchesMarkers(view.accessibilityLabel, MDFOverlayExclusionMarkers())) return YES;
    if (MDFStringMatchesMarkers(view.accessibilityIdentifier, MDFOverlayExclusionMarkers())) return YES;
    NSString *className = NSStringFromClass([view class]).lowercaseString;
    for (NSString *marker in MDFOverlayExclusionMarkers()) {
        if ([className containsString:marker]) return YES;
    }
    return NO;
}

// Second pass: some Facebook builds do not expose accessibility labels on the
// Reels action rail, but the control classes are named ("...ReelsLikeButton",
// "...ReelsCommentView", "...ReelsShareButton", ...). Hiding by class name is a
// good fallback, and the player guard still applies, so a container that owns
// the video is never hidden.
static BOOL MDFClassNameIsReelsControl(UIView *view) {
    NSString *className = NSStringFromClass([view class]).lowercaseString;
    if (![className containsString:@"reel"]) return NO;
    NSArray<NSString *> *controlFragments = @[@"like", @"comment", @"share", @"send",
                                              @"save", @"action", @"button", @"footer",
                                              @"caption", @"audio", @"music", @"ufi",
                                              @"profile", @"follow", @"menu"];
    for (NSString *fragment in controlFragments) {
        if ([className containsString:fragment]) return YES;
    }
    return NO;
}

static void MDFHideReelsControlsByClassName(UIView *view) {
    if (!view) return;
    for (UIView *sub in [view.subviews copy]) {
        MDFHideReelsControlsByClassName(sub);
    }
    if (view == view.window) return;
    if (MDFViewContainsPlayer(view)) return;
    if (MDFViewIsOverlayExcluded(view)) return;
    if (MDFClassNameIsReelsControl(view)) {
        view.hidden = YES;
        MDFLog(@"hid reels control by class: %@", NSStringFromClass([view class]));
    }
}

static void MDFHideOverlayControls(UIView *view) {
    if (!view) return;
    // Recurse first so we hide the deepest control widget rather than a parent
    // that happens to expose a control-like accessibility label.
    for (UIView *sub in [view.subviews copy]) {
        MDFHideOverlayControls(sub);
    }
    if (view == view.window) return;
    if (MDFViewIsControlWidget(view)) {
        view.hidden = YES;
        MDFLog(@"hid reels/stories control: %@", NSStringFromClass([view class]));
    }
}

// Controls can be added after the first pass (the player creates them lazily),
// so a short burst of passes runs first, then a watcher keeps re-applying the
// rule while the viewer is on screen. The old version only ran four passes
// within 2.5s, so anything created later (a new Reel after a swipe, a lazily
// built action rail) was never hidden — that is why the feature looked dead.
static void MDFHideOverlayControlsPass(UIView *view) {
    MDFHideOverlayControls(view);
    MDFHideReelsControlsByClassName(view);
}

@interface MDFReelsOverlayWatcher : NSObject
@property (nonatomic, weak) UIView *root;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSUInteger ticks;
@end

@implementation MDFReelsOverlayWatcher

+ (instancetype)watcherForRoot:(UIView *)root {
    static NSMutableArray<MDFReelsOverlayWatcher *> *watchers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ watchers = [NSMutableArray array]; });

    for (MDFReelsOverlayWatcher *existing in [watchers copy]) {
        if (existing.root == root) return existing;
    }
    MDFReelsOverlayWatcher *watcher = [[MDFReelsOverlayWatcher alloc] init];
    watcher.root = root;
    watcher.ticks = 0;
    [watchers addObject:watcher];
    // 20 ticks x 0.5s = 10s of coverage, which spans a full Reel and the next
    // one, then stops so a long session does not burn CPU.
    watcher.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        UIView *root = watcher.root;
        if (!root || !root.window || watcher.ticks++ > 20) {
            [watcher.timer invalidate];
            watcher.timer = nil;
            return;
        }
        if (MDFPref(@"enabled", YES) && MDFPref(@"hideReelsOverlay", YES)) {
            MDFHideOverlayControlsPass(root);
        }
    }];
    return watcher;
}

@end

static void MDFHideOverlayControlsDeferred(UIView *view) {
    if (!view) return;
    NSArray<NSNumber *> *delays = @[@0.25, @0.75, @1.5, @2.5];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (MDFPref(@"enabled", YES) && MDFPref(@"hideReelsOverlay", YES)) {
                MDFHideOverlayControlsPass(view);
            }
        });
    }
    [MDFReelsOverlayWatcher watcherForRoot:view];
}

#pragma mark - Floating window (settings trigger)
//
// A long-press trigger was unreliable: Facebook installs its own long-press
// recognisers on the feed and they win the gesture arena. A dedicated,
// always-available floating button is deterministic, and a triple tap works
// even when the button is hidden.

@interface MDFPassthroughView : UIView
@end

@implementation MDFPassthroughView
// Let touches through everywhere except on the button itself, so the button
// floats over Facebook without stealing the rest of the screen.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

// A transparent overlay window must not swallow touches. UIKit asks the
// *window* for the hit view, and UIWindow inherits UIView's hitTest:, which
// returns the window itself when no subview claims the point. That is what
// froze Facebook: every touch outside the button was delivered to this window,
// which has nothing to do with it, so Facebook's own window below never saw the
// event. Returning nil here makes UIKit move on to the next window down.
//
// The window is also kept out of the key-window slot by default: an overlay
// that becomes key would take keyboard focus away from Facebook. The alert
// window opts back in via mdfCanBecomeKey.
@interface MDFPassthroughWindow : UIWindow
@property (nonatomic, assign) BOOL mdfCanBecomeKey;
@end

@implementation MDFPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    if (hit == self.rootViewController.view) return nil;
    return hit;
}

- (BOOL)canBecomeKeyWindow {
    return self.mdfCanBecomeKey;
}
@end

@interface MDFFloatingRootViewController : UIViewController
@end

static UIWindow *gMDFFloatingWindow = nil;
static UIButton *gMDFFloatingButton = nil;

@implementation MDFFloatingRootViewController

// The root view is a passthrough view, so touches that miss the button go
// straight to Facebook underneath. It is set here (not in viewDidLoad) because
// loadView is what creates the controller's view.
- (void)loadView {
    self.view = [[MDFPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 52, 52);
    button.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.92];
    button.layer.cornerRadius = 26;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.35;
    button.layer.shadowRadius = 6;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.accessibilityLabel = @"MooDfacebook settings";
    UIImage *gear = [UIImage systemImageNamed:@"gearshape.fill"];
    if (gear) {
        [button setImage:gear forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
    } else {
        [button setTitle:@"M" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    }
    [button addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(dragButton:)]];
    [self.view addSubview:button];
    gMDFFloatingButton = button;

    UIScreen *screen = self.view.window.screen ?: UIScreen.mainScreen;
    CGSize size = screen.bounds.size;
    button.center = CGPointMake(size.width - 40, size.height * 0.62);
    button.hidden = !MDFPref(@"showFloatingButton", YES);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!gMDFFloatingButton) return;
    CGRect bounds = self.view.bounds;
    CGPoint center = gMDFFloatingButton.center;
    center.x = MIN(MAX(center.x, 32), MAX(bounds.size.width - 32, 32));
    center.y = MIN(MAX(center.y, 80), MAX(bounds.size.height - 80, 80));
    gMDFFloatingButton.center = center;
}

- (void)openSettings {
    MDFPresentSettings();
}

- (void)dragButton:(UIPanGestureRecognizer *)recognizer {
    UIView *button = recognizer.view;
    CGPoint translation = [recognizer translationInView:self.view];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [recognizer setTranslation:CGPointZero inView:self.view];
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        CGRect bounds = self.view.bounds;
        CGPoint center = button.center;
        center.x = MIN(MAX(center.x, 32), MAX(bounds.size.width - 32, 32));
        center.y = MIN(MAX(center.y, 80), MAX(bounds.size.height - 80, 80));
        [UIView animateWithDuration:0.2 animations:^{ button.center = center; }];
    }
}

@end

static UIViewController *MDFFloatingRootViewControllerInstance(void) {
    return gMDFFloatingWindow.rootViewController;
}

// Order-independent gesture target: the floating window may not exist yet when
// the key-window recogniser is installed.
@interface MDFSettingsTrigger : NSObject
+ (instancetype)shared;
- (void)trigger;
@end

@implementation MDFSettingsTrigger
+ (instancetype)shared {
    static MDFSettingsTrigger *trigger;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ trigger = [[MDFSettingsTrigger alloc] init]; });
    return trigger;
}
- (void)trigger { MDFPresentSettings(); }
@end

static void MDFSetupUI(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ MDFSetupUI(); });
        return;
    }
    // Fallback trigger: a triple tap on the key window, which does receive
    // touches even though the floating view passes them through.
    UIWindow *keyWindow = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)candidate).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    if (keyWindow && !objc_getAssociatedObject(keyWindow, "mdf.gesture")) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:[MDFSettingsTrigger shared]
                    action:@selector(trigger)];
        tap.numberOfTouchesRequired = 1;
        tap.numberOfTapsRequired = 3;
        tap.cancelsTouchesInView = NO;
        [keyWindow addGestureRecognizer:tap];
        objc_setAssociatedObject(keyWindow, "mdf.gesture", tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (gMDFFloatingWindow) {
        gMDFFloatingButton.hidden = !MDFPref(@"showFloatingButton", YES);
        return;
    }
    // The floating window can only belong to the active scene; creating one
    // while the app is inactive would build it against the wrong window scene.
    BOOL sceneActive = NO;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            sceneActive = YES;
            break;
        }
    }
    if (!sceneActive) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }
    if (!scene) return; // App not foregrounded yet; retried later.

    MDFPassthroughWindow *window = [[MDFPassthroughWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert - 1;
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = [[MDFFloatingRootViewController alloc] init];
    window.hidden = NO;
    gMDFFloatingWindow = window;
    MDFLog(@"floating settings button ready");
}

// Facebook rebuilds its window scene on some transitions. Rebuild the floating
// button against the new scene when that happens.
static void MDFObserveSceneLifecycle(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    for (NSString *name in @[UISceneDidActivateNotification, UISceneWillEnterForegroundNotification]) {
        [center addObserverForName:name object:nil queue:main usingBlock:^(NSNotification *note) {
            (void)note;
            UIWindow *keyWindow = nil;
            for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
                if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *window in ((UIWindowScene *)candidate).windows) {
                    if (window.isKeyWindow) { keyWindow = window; break; }
                }
                if (keyWindow) break;
            }
            if (gMDFFloatingWindow && keyWindow && gMDFFloatingWindow.windowScene != keyWindow.windowScene) {
                gMDFFloatingWindow.hidden = YES;
                gMDFFloatingWindow = nil;
                gMDFFloatingButton = nil;
            }
            MDFSetupUI();
        }];
    }
}

#pragma mark - Presentation helpers

static UIViewController *MDFTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (keyWindow) break;
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

// Present from our own window when possible: Facebook cannot dismiss it, and it
// sits above the Facebook UI.
static UIViewController *MDFSettingsPresenter(void) {
    UIViewController *floating = MDFFloatingRootViewControllerInstance();
    if (floating && floating.view.window) return floating;
    return MDFTopViewController();
}

static void MDFPresentShare(NSURL *fileURL) {
    if (!fileURL) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = MDFTopViewController();
        if (!presenter) return;
        UIActivityViewController *share =
            [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        if (share.popoverPresentationController) {
            share.popoverPresentationController.sourceView = presenter.view;
            share.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
        }
        [presenter presentViewController:share animated:YES completion:nil];
    });
}

static void MDFToast(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = MDFFloatingRootViewControllerInstance();
        UIView *host = root.view.window ? root.view : MDFTopViewController().view;
        if (!host || !message.length) return;
        UILabel *label = [[UILabel alloc] init];
        label.text = message;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
        label.layer.cornerRadius = 10;
        label.clipsToBounds = YES;
        CGSize maxSize = CGSizeMake(host.bounds.size.width - 80, 80);
        CGSize size = [label sizeThatFits:maxSize];
        label.frame = CGRectMake(0, 0, size.width + 32, size.height + 20);
        label.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMaxY(host.bounds) - 120);
        label.alpha = 0;
        [host addSubview:label];
        [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL finished) {
            (void)finished;
            [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ label.alpha = 0; }
                             completion:^(BOOL done) { (void)done; [label removeFromSuperview]; }];
        }];
    });
}

#pragma mark - Settings screen

static UINavigationController *gMDFSettingsNav = nil;

static void MDFResetPrefs(void) {
    NSUserDefaults *suite = MDFSuiteDefaults();
    for (NSString *key in [suite dictionaryRepresentation]) [suite removeObjectForKey:key];
    MDFRegisterDefaults();
}

@interface MDFSettingsViewController : UITableViewController
@end

@implementation MDFSettingsViewController {
    NSArray<NSDictionary *> *_sections;
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"MooDfacebook";
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                          target:self
                                                          action:@selector(doneTapped)];
        [self buildModel];
    }
    return self;
}

- (void)buildModel {
    _sections = @[
        @{ @"title": @"Master", @"footer": @"Turn every feature off without uninstalling.",
           @"rows": @[
               @{ @"key": @"enabled", @"title": @"Enable tweak",
                  @"subtitle": @"Master switch for every feature below", @"type": @"switch" } ] },
        @{ @"title": @"Feed", @"footer": @"Hides matching feed cells entirely.",
           @"rows": @[
               @{ @"key": @"hideAds", @"title": @"Remove ads",
                  @"subtitle": @"Hide sponsored and suggested posts", @"type": @"switch" },
               @{ @"key": @"hidePYMK", @"title": @"Remove People You May Know",
                  @"subtitle": @"Hide friend suggestions and mutual-friend cards", @"type": @"switch" },
               @{ @"key": @"hideReelsCarousel", @"title": @"Remove Reels carousel",
                  @"subtitle": @"Hide the Reels shelf in the feed", @"type": @"switch" } ] },
        @{ @"title": @"Interaction",
           @"footer": @"The confirmation is shown on its own window so it stays on screen.",
           @"rows": @[
               @{ @"key": @"confirmLike", @"title": @"Confirm like",
                  @"subtitle": @"Ask before a post is liked", @"type": @"switch" } ] },
        @{ @"title": @"Downloads", @"footer": @"Long-press a photo, video, Reel or Story.",
           @"rows": @[
               @{ @"key": @"downloadMedia", @"title": @"Download media",
                  @"subtitle": @"Save photos and videos from the feed", @"type": @"switch" },
               @{ @"key": @"downloadReels", @"title": @"Download Reels",
                  @"subtitle": @"Save the Reel that is playing", @"type": @"switch" },
               @{ @"key": @"downloadStories", @"title": @"Download Stories",
                  @"subtitle": @"Save the Story that is playing", @"type": @"switch" },
               @{ @"key": @"showDownloadButton", @"title": @"Download button on media",
                  @"subtitle": @"Floating download icon: above Like in Reels, top-right in Stories",
                  @"type": @"switch" },
               @{ @"key": @"shareAfterDownload", @"title": @"Open share sheet after download",
                  @"subtitle": @"Videos only; off copies the media link instead", @"type": @"switch" } ] },
        @{ @"title": @"Reels and Stories",
           @"footer": @"Overlay hiding never touches the video player, so playback stays visible.",
           @"rows": @[
               @{ @"key": @"hideReelsOverlay", @"title": @"Hide Reels overlay",
                  @"subtitle": @"Hide like, comment, share and caption controls", @"type": @"switch" },
               @{ @"key": @"incognitoStories", @"title": @"Incognito Stories",
                  @"subtitle": @"Watch Stories without leaving a seen receipt", @"type": @"switch" } ] },
        @{ @"title": @"Interface",
           @"footer": @"Triple-tap the screen to open this settings screen at any time.",
           @"rows": @[
               @{ @"key": @"showFloatingButton", @"title": @"Floating settings button",
                  @"subtitle": @"Draggable gear button over the Facebook UI", @"type": @"switch" },
               @{ @"key": @"debug", @"title": @"Debug logging",
                  @"subtitle": @"Write [MooDfacebook] lines to the system log", @"type": @"switch" } ] },
        @{ @"title": @"About", @"footer": @"MooDfacebook for RootHide, iOS 18 / arm64e.",
           @"rows": @[
               @{ @"key": @"version", @"title": @"Version", @"value": MDF_VERSION, @"type": @"info" },
               @{ @"key": @"reset", @"title": @"Reset all settings", @"type": @"action" } ] },
    ];
}

- (void)doneTapped {
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        gMDFSettingsNav = nil;
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[_sections[(NSUInteger)section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return _sections[(NSUInteger)section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return _sections[(NSUInteger)section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = _sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    NSString *type = row[@"type"];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.text = row[@"subtitle"] ?: row[@"value"];
    cell.detailTextLabel.numberOfLines = 2;

    if ([type isEqualToString:@"switch"]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.onTintColor = [UIColor colorWithRed:0.11 green:0.43 blue:0.94 alpha:1.0];
        toggle.on = MDFPref(row[@"key"], YES);
        toggle.tag = (indexPath.section << 8) | indexPath.row;
        toggle.accessibilityLabel = row[@"title"];
        [toggle addTarget:self action:@selector(switchChanged:)
         forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"info"]) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    } else {
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.detailTextLabel.text = nil;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSInteger section = sender.tag >> 8;
    NSInteger row = sender.tag & 0xFF;
    if (section >= (NSInteger)_sections.count) return;
    NSArray *rows = _sections[(NSUInteger)section][@"rows"];
    if (row >= (NSInteger)rows.count) return;
    NSDictionary *rowInfo = rows[(NSUInteger)row];

    MDFSetPref(rowInfo[@"key"], sender.on);
    MDFLog(@"setting %@ = %d", rowInfo[@"key"], sender.on);

    if ([rowInfo[@"key"] isEqualToString:@"showFloatingButton"] && gMDFFloatingButton) {
        gMDFFloatingButton.hidden = !sender.on;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = _sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    if ([row[@"type"] isEqualToString:@"action"] && [row[@"key"] isEqualToString:@"reset"]) {
        MDFResetPrefs();
        [self.tableView reloadData];
        MDFToast(@"Settings reset");
    }
}

@end

static void MDFPresentSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // A page sheet can be dismissed by swiping down, which never runs
        // doneTapped, so a controller that is no longer presented counts as
        // closed and the screen stays reachable.
        if (gMDFSettingsNav && gMDFSettingsNav.presentingViewController) return;
        gMDFSettingsNav = nil;
        UIViewController *presenter = MDFSettingsPresenter();
        if (!presenter) { MDFLog(@"no presenter for settings"); return; }
        MDFSettingsViewController *settings = [[MDFSettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        gMDFSettingsNav = nav;
        [presenter presentViewController:nav animated:YES completion:^{
            MDFLog(@"settings presented");
        }];
    });
}

#pragma mark - Confirm-like alert (threading fix)
//
// The old alert flashed and vanished. Three causes:
//   1. It was presented from `MDFTopViewController()`, which could be a
//      Facebook controller that was already being dismissed or replaced, so
//      UIKit tore the alert down on the very next run loop.
//   2. `presentViewController:` could run off the main thread (the like action
//      is not guaranteed to arrive on main), which makes UIKit drop or
//      immediately dismiss the presentation.
//   3. Re-entrancy: the prompt could be raised twice for one tap, and the second
//      presentation dismissed the first — the visible "flash".
//
// The fix: present from a dedicated UIWindow owned by the tweak, always on the
// main thread, with an in-flight guard, and let the confirmed action through by
// matching its exact target/action pair rather than a global flag.

@interface MDFAlertRootViewController : UIViewController
@end

@implementation MDFAlertRootViewController
// Passthrough root as well, so a transparent alert window can never trap
// touches if the alert itself fails to present. The alert's own view is a
// subview and still receives touches normally.
- (void)loadView {
    self.view = [[MDFPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
}
@end

static UIWindow *gMDFAlertWindow = nil;
static BOOL gMDFConfirmInFlight = NO; // an alert is on screen

// The confirmed action is allowed through by matching the exact target/action
// pair instead of a global flag. A global flag is racy: the like action may be
// re-sent asynchronously (after the flag was cleared) or not re-sent at all
// (leaving the flag armed for the next genuine like). The match is one-shot.
static __weak id gMDFConfirmTarget = nil;
static SEL gMDFConfirmAction = NULL;

static void MDFArmConfirmBypass(id target, SEL action) {
    gMDFConfirmTarget = target;
    gMDFConfirmAction = action;
}

static BOOL MDFConsumeConfirmBypass(id target, SEL action) {
    if (gMDFConfirmAction == NULL || action != gMDFConfirmAction) return NO;
    if (gMDFConfirmTarget != target) return NO;
    gMDFConfirmTarget = nil;
    gMDFConfirmAction = NULL;
    return YES;
}

static void MDFClearConfirmBypass(void) {
    gMDFConfirmTarget = nil;
    gMDFConfirmAction = NULL;
}

static void MDFDismissAlertWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = gMDFAlertWindow;
        gMDFAlertWindow = nil;
        MDFClearConfirmBypass();
        if (!window) return;
        UIViewController *root = window.rootViewController;
        [root dismissViewControllerAnimated:YES completion:^{
            window.hidden = YES;
            window.rootViewController = nil;
        }];
    });
}

static void MDFShowConfirmLike(dispatch_block_t onConfirm) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gMDFAlertWindow) return; // one alert at a time
        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:[UIWindowScene class]] &&
                candidate.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
        if (!scene) {
            for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
                if ([candidate isKindOfClass:[UIWindowScene class]]) {
                    scene = (UIWindowScene *)candidate;
                    break;
                }
            }
        }
        if (!scene) { gMDFConfirmInFlight = NO; onConfirm(); return; }

        // Passthrough window as well: if the alert ever fails to present, this
        // transparent window must not become a touch blocker over Facebook.
        MDFPassthroughWindow *window = [[MDFPassthroughWindow alloc] initWithWindowScene:scene];
        window.mdfCanBecomeKey = YES;
        window.frame = scene.coordinateSpace.bounds;
        window.windowLevel = UIWindowLevelAlert;
        window.backgroundColor = UIColor.clearColor;
        MDFAlertRootViewController *root = [[MDFAlertRootViewController alloc] init];
        window.rootViewController = root;
        window.hidden = NO;
        gMDFAlertWindow = window;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm like"
                                                                      message:@"Do you want to like this post?"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Like"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            (void)action;
            gMDFConfirmInFlight = NO;
            if (onConfirm) onConfirm();
            MDFDismissAlertWindow();
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:^(UIAlertAction *action) {
            (void)action;
            gMDFConfirmInFlight = NO;
            MDFDismissAlertWindow();
        }]];
        [root presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Download helpers
//
// Facebook serves video over HLS, so the URL is usually an .m3u8 playlist, not
// a media file. Downloading the playlist with NSURLSession yields a text file,
// not a video — which is why the old download "worked" but produced nothing
// usable. Playlists are parsed and every segment is fetched, then the segments
// are concatenated into a single .ts file.

static void MDFFinishDownload(NSURL *localFile, NSURL *remoteURL) {
    if (MDFPref(@"shareAfterDownload", YES)) {
        MDFPresentShare(localFile);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIPasteboard.generalPasteboard.URL = remoteURL;
            MDFToast(@"Link copied");
        });
    }
}

// Reads a playlist and resolves every segment URL, following the media playlist
// that a master playlist points at.
static void MDFDownloadHLS(NSURL *playlistURL, NSURL *originalURL, NSUInteger depth) {
    if (depth > 3) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:playlistURL];
    request.timeoutInterval = 30;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (!data.length) {
            MDFLog(@"hls playlist failed: %@", error);
            return;
        }
        NSString *playlist = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!playlist.length) return;

        NSMutableArray<NSString *> *segmentLines = [NSMutableArray array];
        NSMutableArray<NSString *> *variantLines = [NSMutableArray array];
        for (NSString *rawLine in [playlist componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet newlineCharacterSet]]) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            if (!line.length) continue;
            if ([line hasPrefix:@"#"]) continue;
            [segmentLines addObject:line];
            if ([line containsString:@".m3u8"]) [variantLines addObject:line];
        }

        // A master playlist lists variant streams; follow the first one.
        if (segmentLines.count == 0 && variantLines.count > 0) {
            NSURL *variant = [NSURL URLWithString:variantLines.firstObject relativeToURL:playlistURL];
            MDFDownloadHLS(variant.absoluteURL, originalURL, depth + 1);
            return;
        }
        if (segmentLines.count == 0) {
            MDFLog(@"hls playlist had no segments");
            return;
        }

        NSMutableArray<NSURL *> *segments = [NSMutableArray array];
        for (NSString *line in segmentLines) {
            NSURL *segment = [NSURL URLWithString:line relativeToURL:playlistURL];
            if (segment.absoluteURL) [segments addObject:segment.absoluteURL];
        }
        MDFLog(@"hls: %lu segments", (unsigned long)segments.count);

        // Segments must be concatenated in playlist order, so the index is
        // written to a per-segment file and merged afterwards.
        NSString *workDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"mdf-hls-%@", NSUUID.UUID.UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:workDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        dispatch_group_t group = dispatch_group_create();
        for (NSUInteger i = 0; i < segments.count; i++) {
            dispatch_group_enter(group);
            NSURL *segmentURL = segments[i];
            NSUInteger index = i;
            [[[NSURLSession sharedSession] dataTaskWithURL:segmentURL
                                         completionHandler:^(NSData *segmentData, NSURLResponse *r, NSError *e) {
                (void)r; (void)e;
                if (segmentData.length) {
                    NSString *part = [workDir stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"%06lu.part", (unsigned long)index]];
                    [segmentData writeToFile:part atomically:YES];
                }
                dispatch_group_leave(group);
            }] resume];
        }
        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *output = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"MooDfacebook-%@.ts", NSUUID.UUID.UUIDString]];
            [[NSFileManager defaultManager] createFileAtPath:output contents:nil attributes:nil];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:output];
            for (NSUInteger i = 0; i < segments.count; i++) {
                NSString *part = [workDir stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"%06lu.part", (unsigned long)i]];
                NSData *segmentData = [NSData dataWithContentsOfFile:part];
                if (segmentData.length) [handle writeData:segmentData];
            }
            [handle closeFile];
            [[NSFileManager defaultManager] removeItemAtPath:workDir error:NULL];
            MDFLog(@"hls saved to %@", output);
            MDFFinishDownload([NSURL fileURLWithPath:output], originalURL);
        });
    }] resume];
}

static void MDFDownloadAndShare(NSURL *remoteURL) {
    if (!remoteURL) return;
    MDFLog(@"downloading %@", remoteURL.absoluteString);
    dispatch_async(dispatch_get_main_queue(), ^{ MDFToast(@"Downloading…"); });

    BOOL looksLikePlaylist = [remoteURL.pathExtension.lowercaseString isEqualToString:@"m3u8"];
    if (looksLikePlaylist) {
        MDFDownloadHLS(remoteURL, remoteURL, 0);
        return;
    }

    [[[NSURLSession sharedSession] downloadTaskWithURL:remoteURL
                                     completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location) { MDFLog(@"download failed: %@", error); return; }
        NSData *head = [NSData dataWithContentsOfFile:location.path
                                              options:NSDataReadingMappedIfSafe error:NULL];
        // A plain download can still return a playlist (Facebook sometimes
        // serves .m3u8 without the extension), so sniff the body.
        if (head.length) {
            NSString *prefix = [[NSString alloc] initWithData:[head subdataWithRange:
                NSMakeRange(0, MIN(head.length, 64))] encoding:NSUTF8StringEncoding];
            if ([prefix containsString:@"#EXTM3U"]) {
                MDFDownloadHLS(remoteURL, remoteURL, 0);
                return;
            }
        }
        NSString *name = remoteURL.lastPathComponent.length ? remoteURL.lastPathComponent : @"MooDfacebook-media";
        if (![name containsString:@"."]) name = [name stringByAppendingPathExtension:@"mp4"];
        NSURL *target = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        [[NSFileManager defaultManager] removeItemAtURL:target error:NULL];
        NSError *moveError = nil;
        if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:target error:&moveError]) {
            MDFLog(@"move failed: %@", moveError);
            return;
        }
        MDFFinishDownload(target, remoteURL);
    }] resume];
}

static void MDFSaveAndShareImage(UIImage *image) {
    if (!image) return;
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"MooDfacebook-%@.png", NSUUID.UUID.UUIDString]];
    if (![data writeToFile:path atomically:YES]) return;
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    // Facebook's Info.plist has no photo-library usage description, so writing
    // to the camera roll would raise and crash. The share sheet is the safe
    // path for images; the download toggle only changes the fallback hint.
    MDFPresentShare(fileURL);
}

#pragma mark - Download button overlay
//
// A small, always-visible download button is placed on media, because the
// long-press trigger is unreliable inside Facebook's gesture stack: Facebook
// installs its own recognisers and they frequently win the arena.
//
// Placement follows the requirement:
//   * Reels / videos: left side, directly above the Like button.
//   * Stories:        top-right corner.
// The button re-positions itself on every layout pass, so it follows the Like
// button even when the action rail is rebuilt or the device rotates.

static UIButton *MDFMakeDownloadButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 40);
    button.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.55];
    button.layer.cornerRadius = 20;
    button.accessibilityIdentifier = kMDFDownloadButtonIdentifier;
    button.accessibilityLabel = @"Download";
    UIImage *icon = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
    if (icon) {
        [button setImage:icon forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
    } else {
        [button setTitle:@"⤓" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    return button;
}

@interface MDFDownloadButtonTarget : NSObject
+ (instancetype)shared;
- (void)tapped:(UIButton *)sender;
@end

@implementation MDFDownloadButtonTarget
+ (instancetype)shared {
    static MDFDownloadButtonTarget *target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [[MDFDownloadButtonTarget alloc] init]; });
    return target;
}

- (void)tapped:(UIButton *)sender {
    if (!MDFPref(@"enabled", YES)) return;
    if (!MDFPref(@"showDownloadButton", YES)) return;
    UIView *host = sender.superview;
    NSString *scope = objc_getAssociatedObject(sender, "mdf.scope");
    MDFLog(@"download button tapped, scope=%@", scope);

    BOOL allowed = MDFPref(@"downloadMedia", YES);
    if ([scope isEqualToString:kMDFScopeReels]) allowed = MDFPref(@"downloadReels", YES);
    if ([scope isEqualToString:kMDFScopeStories]) allowed = MDFPref(@"downloadStories", YES);
    if (!allowed) { MDFToast(@"Downloading is off for this section"); return; }

    NSURL *video = MDFVideoURLInView(host);
    if (video) { MDFDownloadAndShare(video); return; }
    UIImage *image = MDFImageInView(host);
    if (image) { MDFSaveAndShareImage(image); return; }
    MDFToast(@"No media found here");
}
@end

// Finds the Like button in the action rail so the download button can sit
// directly above it. Facebook labels it, so the accessibility label is the most
// reliable signal; the class name is the fallback.
static UIView *MDFFindLikeControl(UIView *view, NSUInteger depth) {
    if (!view || depth > 10) return nil;
    NSString *label = view.accessibilityLabel.lowercaseString;
    NSString *identifier = view.accessibilityIdentifier.lowercaseString;
    NSString *className = NSStringFromClass([view class]).lowercaseString;
    BOOL labelLike = label.length && ([label containsString:@"like"] ||
                                      [label containsString:@"إعجاب"] ||
                                      [label containsString:@"أعجبني"]);
    BOOL identifierLike = identifier.length && [identifier containsString:@"like"];
    BOOL classLike = [className containsString:@"like"];
    if ((labelLike || identifierLike || classLike) &&
        [view isKindOfClass:[UIControl class]]) {
        return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *found = MDFFindLikeControl(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static BOOL MDFViewIsDownloadButton(UIView *view) {
    return [view.accessibilityIdentifier isEqualToString:kMDFDownloadButtonIdentifier];
}

// Walks the viewer and positions one download button. Called repeatedly, so it
// must be idempotent: it reuses the existing button instead of adding another.
static void MDFUpdateDownloadButton(UIView *root, NSString *scope) {
    if (!root || !scope.length) return;
    if (!MDFPref(@"enabled", YES) || !MDFPref(@"showDownloadButton", YES)) return;

    UIButton *button = nil;
    for (UIView *sub in root.subviews) {
        if (MDFViewIsDownloadButton(sub)) { button = (UIButton *)sub; break; }
    }
    if (!button) {
        button = MDFMakeDownloadButton();
        objc_setAssociatedObject(button, "mdf.scope", scope, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [button addTarget:[MDFDownloadButtonTarget shared]
                   action:@selector(tapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:button];
        [root bringSubviewToFront:button];
    }
    [root bringSubviewToFront:button];

    CGRect bounds = root.bounds;
    if ([scope isEqualToString:kMDFScopeStories]) {
        // Stories: top-right corner, clear of the status bar.
        CGFloat top = root.safeAreaInsets.top + 12;
        button.center = CGPointMake(bounds.size.width - 36, top + 20);
    } else {
        // Reels / videos: left side, directly above the Like button.
        UIView *like = MDFFindLikeControl(root, 0);
        if (like) {
            CGRect likeFrame = [like convertRect:like.bounds toView:root];
            button.center = CGPointMake(likeFrame.origin.x + likeFrame.size.width / 2,
                                        likeFrame.origin.y - 34);
        } else {
            // No Like button found (or it is off-screen): fall back to a stable
            // spot on the left rail, vertically centred.
            button.center = CGPointMake(36, bounds.size.height * 0.62);
        }
    }
    button.hidden = NO;
}

static void MDFUpdateDownloadButtonDeferred(UIView *root, NSString *scope) {
    if (!root || !scope.length) return;
    NSArray<NSNumber *> *delays = @[@0.1, @0.4, @0.9, @1.6, @2.4];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MDFUpdateDownloadButton(root, scope);
        });
    }
}

// Feed cells (photos and videos in the timeline). The button is pinned to the
// media area rather than the whole cell, so it does not overlap the caption.
static void MDFAttachDownloadButtonToCell(UIView *cell) {
    if (!cell) return;
    if (!MDFPref(@"enabled", YES) || !MDFPref(@"showDownloadButton", YES)) return;
    if (!MDFPref(@"downloadMedia", YES)) return;
    if (!MDFFeedContainerAncestor(cell)) return;
    if (cell.hidden) return;
    // Only add the button to cells that actually contain media.
    if (!MDFViewContainsPlayer(cell) && !MDFImageInView(cell)) return;
    MDFUpdateDownloadButton(cell, kMDFScopeMedia);
}

@interface MDFMediaGestureHandler : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation MDFMediaGestureHandler

+ (instancetype)shared {
    static MDFMediaGestureHandler *handler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handler = [[MDFMediaGestureHandler alloc] init]; });
    return handler;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    if (!MDFPref(@"enabled", YES)) return;

    NSString *scope = objc_getAssociatedObject(recognizer, "mdf.scope");
    BOOL allowed = MDFPref(@"downloadMedia", YES);
    if ([scope isEqualToString:kMDFScopeReels]) allowed = MDFPref(@"downloadReels", YES);
    if ([scope isEqualToString:kMDFScopeStories]) allowed = MDFPref(@"downloadStories", YES);
    if (!allowed) return;

    UIView *host = recognizer.view;
    NSURL *video = MDFVideoURLInView(host);
    if (video) { MDFDownloadAndShare(video); return; }
    UIImage *image = MDFImageInView(host);
    if (image) { MDFSaveAndShareImage(image); return; }
    // The gesture fired but there was nothing downloadable under the touch.
    // Reporting it makes the feature observable instead of looking broken.
    MDFToast(@"No media found here");
}

@end

static void MDFInstallLongPress(UIView *host, NSString *scope) {
    if (!host) return;
    for (UIGestureRecognizer *recognizer in host.gestureRecognizers) {
        if ([recognizer.name isEqualToString:kMDFLongPressName]) return;
    }
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:[MDFMediaGestureHandler shared]
                                                      action:@selector(handleLongPress:)];
    press.name = kMDFLongPressName;
    press.minimumPressDuration = 0.6;
    press.cancelsTouchesInView = NO;
    objc_setAssociatedObject(press, "mdf.scope", scope, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [host addGestureRecognizer:press];
}

#pragma mark - Feed cell processing
//
// Cell recycling is the subtle part. Facebook reuses cell objects as you
// scroll, so a cell that was hidden for one post is handed back for a different
// post. The old code only ever set hidden = YES and never cleared it, so once a
// sponsored post scrolled past, every later post that reused that cell object
// stayed invisible. That is why the whole feed sometimes disappeared and
// sometimes nothing happened at all: it depended on which cells got recycled.
//
// The rule is therefore symmetric: decide the state on every layout pass and
// assign it, so a recycled cell is always restored before being re-evaluated.
// The decision is also cached per cell so a cell that matched once keeps its
// state even if its subviews are rebuilt.

static void *kMDFCellDecisionKey = &kMDFCellDecisionKey;

static BOOL MDFCellShouldHide(UIView *cell) {
    // Only touch cells that live in a feed container: this keeps the hooks from
    // hiding cells in unrelated collection/table views (for example a picker).
    if (!MDFFeedContainerAncestor(cell)) return NO;

    // The header is the top band of the cell: author line + "Sponsored" badge.
    // Only that band is scanned for ads, so a post whose body text merely
    // contains the word "sponsored" is not hidden.
    BOOL hideAds = MDFPref(@"hideAds", YES);
    BOOL hidePYMK = MDFPref(@"hidePYMK", YES);
    BOOL hideReelsCarousel = MDFPref(@"hideReelsCarousel", YES);
    if (!hideAds && !hidePYMK && !hideReelsCarousel) return NO;

    if (hideAds) {
        if (MDFViewShallowMatchesMarkers(cell, MDFAdMarkers(), 3)) return YES;
        if (MDFViewIdentifierMatchesMarkers(cell, MDFAdIdentifierMarkers())) return YES;
        if (MDFViewMatchesClassNames(cell, MDFAdClassMarkers())) return YES;
    }
    if (hidePYMK) {
        if (MDFViewShallowMatchesMarkers(cell, MDFPYMKMarkers(), 4)) return YES;
        if (MDFViewShallowMatchesMarkers(cell, MDFSuggestedMarkers(), 4)) return YES;
    }
    if (hideReelsCarousel) {
        // The Reels shelf is identified primarily by its *class*, not by loose
        // text: a normal video post also contains the word "reels" in its body,
        // which is what made this feature hide ordinary posts. The text marker
        // is therefore only consulted at depth 2, where the shelf's own header
        // ("Reels and short videos") lives — never the post body.
        if (MDFViewMatchesClassNames(cell, MDFReelsShelfClassMarkers())) return YES;
        if (MDFViewShallowMatchesMarkers(cell, MDFReelsMarkers(), 2)) return YES;
    }
    return NO;
}

static void MDFProcessFeedCell(UIView *cell) {
    if (!MDFPref(@"enabled", YES)) return;

    BOOL shouldHide = MDFCellShouldHide(cell);
    NSNumber *previous = objc_getAssociatedObject(cell, kMDFCellDecisionKey);
    if (!previous || previous.boolValue != shouldHide) {
        objc_setAssociatedObject(cell, kMDFCellDecisionKey,
                                 @(shouldHide), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (shouldHide) {
            MDFLog(@"hiding feed cell %@", NSStringFromClass([cell class]));
        }
    }
    if (cell.hidden != shouldHide) cell.hidden = shouldHide;

    if (!shouldHide) MDFDumpCellText(cell);

    if (MDFPref(@"downloadMedia", YES)) MDFInstallLongPress(cell, kMDFScopeMedia);
    MDFAttachDownloadButtonToCell(cell);
}

#pragma mark - Incognito Stories (no seen receipt)
//
// Two bugs made this feature dead. First, the class-name test was
// case-sensitive ("Story" never matched a class named "...story...").
// Second, the scan ran once at load time, on a background queue, before
// Facebook had even loaded its Story classes — so there was nothing to hook.
// The scan now runs case-insensitively and is retried a few times after launch.

static void MDFNoopIMP(void) {}

// Methods that must never be no-op'd even though they look like seen-tracking:
// a getter returning a value would leave the return register undefined.
static BOOL MDFSelectorIsGetter(const char *selectorName) {
    return strncmp(selectorName, "is", 2) == 0 ||
           strncmp(selectorName, "has", 3) == 0 ||
           strncmp(selectorName, "get", 3) == 0;
}

static BOOL MDFClassNameLooksLikeStory(const char *className) {
    if (!className) return NO;
    // Case-insensitive so "FBStory", "storyviewer" and "StorySeenState" all hit.
    static const char *needles[] = {"story", "stories"};
    for (size_t i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) {
        const char *needle = needles[i];
        size_t needleLength = strlen(needle);
        size_t classNameLength = strlen(className);
        if (classNameLength < needleLength) continue;
        for (size_t start = 0; start + needleLength <= classNameLength; start++) {
            if (strncasecmp(className + start, needle, needleLength) == 0) return YES;
        }
    }
    return NO;
}

static BOOL MDFSelectorLooksLikeSeenTracking(const char *selectorName) {
    if (!selectorName) return NO;
    static const char *needles[] = {"markstoryseen", "markseen", "setstoryseen",
                                    "reportseen", "storyseen", "markasseen",
                                    "didseestory", "setseen", "seenstory"};
    for (size_t i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) {
        if (strcasestr(selectorName, needles[i])) return YES;
    }
    return NO;
}

static void MDFDisableStorySeenTracking(void) {
    if (!MDFPref(@"incognitoStories", YES)) return;
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        const char *className = class_getName(cls);
        if (!MDFClassNameLooksLikeStory(className)) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        for (unsigned int j = 0; j < methodCount; j++) {
            Method method = methods[j];
            const char *selectorName = sel_getName(method_getName(method));
            if (!MDFSelectorLooksLikeSeenTracking(selectorName)) continue;
            if (MDFSelectorIsGetter(selectorName)) continue;
            // Only replace methods that return void: a no-op IMP on a method
            // that returns a value would leave the return register undefined.
            const char *types = method_getTypeEncoding(method);
            if (!types || types[0] != 'v') continue;
            method_setImplementation(method, (IMP)MDFNoopIMP);
            MDFLog(@"incognito: disabled %s -%s", className, selectorName);
        }
        free(methods);
    }
    free(classes);
}

// Facebook loads its Story classes lazily, so the scan is retried after launch
// instead of running only once.
static void MDFScheduleIncognitoScan(void) {
    NSArray<NSNumber *> *delays = @[@0.5, @3.0, @8.0, @20.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            MDFDisableStorySeenTracking();
        });
    }
}

#pragma mark - Reels / Stories controller handling

static void MDFHandleViewControllerAppear(UIViewController *controller) {
    if (!controller) return;
    if (!MDFPref(@"enabled", YES)) return;

    NSString *className = NSStringFromClass([controller class]).lowercaseString;
    BOOL isReels = [className containsString:@"reel"];
    BOOL isStory = [className containsString:@"story"];

    if (isReels) {
        if (MDFPref(@"hideReelsOverlay", YES)) {
            MDFHideOverlayControls(controller.view);
            MDFHideReelsControlsByClassName(controller.view);
            MDFHideOverlayControlsDeferred(controller.view);
        }
        if (MDFPref(@"downloadReels", YES)) {
            MDFInstallLongPress(controller.view, kMDFScopeReels);
            MDFUpdateDownloadButton(controller.view, kMDFScopeReels);
            MDFUpdateDownloadButtonDeferred(controller.view, kMDFScopeReels);
        }
    } else if (isStory) {
        if (MDFPref(@"downloadStories", YES)) {
            MDFInstallLongPress(controller.view, kMDFScopeStories);
            MDFUpdateDownloadButton(controller.view, kMDFScopeStories);
            MDFUpdateDownloadButtonDeferred(controller.view, kMDFScopeStories);
        }
    }
}

#pragma mark - Hooks


// Confirm before liking.
//
// This is the threading fix: the prompt is raised on the main thread from a
// dedicated window (see MDFShowConfirmLike), and the confirmed action re-enters
// this hook with its target/action armed so it falls through to %orig instead of
// prompting again. The cheap selector test runs first so the hot path does not
// touch NSUserDefaults on every control action.
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (MDFConsumeConfirmBypass(target, action)) {
        %orig;
        return;
    }

    const char *selectorName = sel_getName(action);
    BOOL looksLikeLike = selectorName &&
        (strstr(selectorName, "like") || strstr(selectorName, "Like") ||
         strstr(selectorName, "react") || strstr(selectorName, "React"));

    if (!looksLikeLike) {
        NSString *a11y = self.accessibilityLabel;
        NSString *identifier = self.accessibilityIdentifier;
        if (a11y.length || identifier.length) {
            NSString *haystack = [[NSString stringWithFormat:@"%@ %@", a11y ?: @"", identifier ?: @""] lowercaseString];
            looksLikeLike = [haystack containsString:@"like"] ||
                             [haystack containsString:@"إعجاب"] ||
                             [haystack containsString:@"أعجبني"];
        }
    }

    if (looksLikeLike && !gMDFConfirmInFlight &&
        MDFPref(@"enabled", YES) && MDFPref(@"confirmLike", YES)) {
        gMDFConfirmInFlight = YES;
        __weak UIControl *weakSelf = self;
        SEL actionCopy = action;
        id targetCopy = target;
        UIEvent *eventCopy = event;
        MDFShowConfirmLike(^{
            UIControl *strongSelf = weakSelf;
            if (!strongSelf) return;
            MDFArmConfirmBypass(targetCopy, actionCopy);
            [strongSelf sendAction:actionCopy to:targetCopy forEvent:eventCopy];
        });
        return;
    }
    %orig;
}
%end

// Feed cells: sponsored, suggested, People You May Know, Reels shelf, and the
// long-press download target. UICollectionViewCell and UITableViewCell both
// implement layoutSubviews themselves, so hooking them is safe.
%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    MDFProcessFeedCell(self);
}
%end

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    MDFProcessFeedCell(self);
}
%end

// Reels / Stories viewers. UIViewController implements viewDidAppear itself, so
// this hook is safe; the viewer type is decided by class name at runtime.
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    MDFHandleViewControllerAppear(self);
}
%end

// Remember the URL of the item being played so a download can resolve it. The
// item is hooked as well as the player: Facebook often builds the item first and
// hands it to a player we never see, so the item carries the URL either way.
%hook AVPlayerItem
- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    if (self && URL) objc_setAssociatedObject(self, "mdf.mediaURL", URL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (instancetype)initWithAsset:(AVAsset *)asset {
    self = %orig;
    if (self) {
        NSURL *url = MDFResolveAssetURL(asset);
        if (url) objc_setAssociatedObject(self, "mdf.mediaURL", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}
%end

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    NSURL *url = objc_getAssociatedObject(item, "mdf.mediaURL");
    if (!url) url = MDFResolveAssetURL(item.asset);
    if (url) {
        objc_setAssociatedObject(self, "mdf.mediaURL", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MDFLog(@"playing %@", url.absoluteString);
    }
}
%end

// Attach the floating settings button once the app window is up.
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    MDFSetupUI();
}
%end


%ctor {
    MDFRegisterDefaults();
    MDFObserveSceneLifecycle();
    // Facebook loads its Story classes lazily, so the incognito scan is retried
    // after launch instead of running once on the launch-critical path.
    MDFScheduleIncognitoScan();
    // Fallback in case makeKeyAndVisible ran before the tweak was injected.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MDFSetupUI();
    });
    MDFLog(@"MooDfacebook %@ loaded", MDF_VERSION);
}
