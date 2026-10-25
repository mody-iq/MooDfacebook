// MooDfacebook — RootHide (roothide) tweak for Facebook (com.facebook.Facebook)
// iOS 18.x / arm64e.
//
// Features
//   1. Remove ads / sponsored + suggested posts
//   2. Remove "People you may know"
//   3. Hide the Reels carousel / shelf
//   4. Confirm before a post is liked
//   5. Download media on long press
//   6. Download Reels and hide the Reels overlay
//   7. Download Stories and watch them incognito (no seen receipt)
//
// Preferences are read from the NSUserDefaults suite com.mody-iq.moodfacebook
// so the tweak works with no preference bundle installed (safe defaults below).

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Facebook internal class declarations

// Facebook's UI classes are private. Declaring their real supertype lets the
// compiler resolve inherited members (view, hidden, subviews, layer, ...)
// without shipping Facebook headers.
@interface FBReelsShelfView : UIView @end
@interface FBReelsViewerViewController : UIViewController @end
@interface FBReelsViewController : UIViewController @end
@interface FBStoryViewerViewController : UIViewController @end

#pragma mark - Preferences

static NSString *const kMDFSuite = @"com.mody-iq.moodfacebook";
static NSString *const kMDFConfirmFlag = @"mdf.confirming";

static BOOL MDFPref(NSString *key, BOOL fallback) {
    NSNumber *value = [[[NSUserDefaults alloc] initWithSuiteName:kMDFSuite] objectForKey:key];
    return value ? value.boolValue : fallback;
}

static BOOL MDFDebug(void) {
    return MDFPref(@"debug", NO);
}

#define MDFLog(fmt, ...) do { if (MDFDebug()) NSLog(@"[MooDfacebook] " fmt, ##__VA_ARGS__); } while (0)

#pragma mark - Marker tables

static NSArray<NSString *> *MDFAdMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"Sponsored", @"مموّل", @"ممول", @"Sponsorisé", @"Patrocinado",
                    @"Sponsorizzato", @"Anzeige", @"Publicidad", @"Реклама", @"Gesponsert"];
    });
    return markers;
}

static NSArray<NSString *> *MDFPYMKMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"People you may know", @"People You May Know", @"أشخاص قد تعرفهم",
                    @"Suggested for you", @"مقترح لك", @"Suggestions"];
    });
    return markers;
}

static NSArray<NSString *> *MDFReelsMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"Reels and short videos", @"مقاطع ريلز", @"Reels"];
    });
    return markers;
}

static NSArray<NSString *> *MDFOverlayMarkers(void) {
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"Like", @"Comment", @"Share", @"Send", @"إعجاب", @"تعليق", @"مشاركة", @"إرسال"];
    });
    return markers;
}

#pragma mark - View helpers

static void MDFCollectText(UIView *view, NSMutableArray<NSString *> *out, NSUInteger depth) {
    if (!view || depth > 5 || out.count > 80) return;
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length) [out addObject:text];
    }
    if (view.accessibilityLabel.length) [out addObject:view.accessibilityLabel];
    if (view.accessibilityIdentifier.length) [out addObject:view.accessibilityIdentifier];
    for (UIView *sub in view.subviews) MDFCollectText(sub, out, depth + 1);
}

static BOOL MDFViewMatchesMarkers(UIView *view, NSArray<NSString *> *markers) {
    if (!view) return NO;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    MDFCollectText(view, texts, 0);
    for (NSString *text in texts) {
        NSString *haystack = text.lowercaseString;
        for (NSString *marker in markers) {
            if ([haystack containsString:marker.lowercaseString]) return YES;
        }
    }
    return NO;
}

static NSURL *MDFVideoURLInView(UIView *view) {
    if (!view) return nil;
    if ([view.layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *player = ((AVPlayerLayer *)view.layer).player;
        AVPlayerItem *item = player.currentItem;
        AVAsset *asset = item.asset;
        if ([asset isKindOfClass:[AVURLAsset class]]) return ((AVURLAsset *)asset).URL;
    }
    for (UIView *sub in view.subviews) {
        NSURL *url = MDFVideoURLInView(sub);
        if (url) return url;
    }
    return nil;
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

static void MDFHideOverlayInView(UIView *view) {
    if (!view) return;
    if (view != view.window && MDFViewMatchesMarkers(view, MDFOverlayMarkers())) {
        view.hidden = YES;
        return;
    }
    for (UIView *sub in view.subviews) MDFHideOverlayInView(sub);
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

static void MDFPresentShare(NSURL *fileURL) {
    if (!fileURL) return;
    UIViewController *top = MDFTopViewController();
    if (!top) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *share =
            [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        if (share.popoverPresentationController) {
            share.popoverPresentationController.sourceView = top.view;
            share.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
        }
        [top presentViewController:share animated:YES completion:nil];
    });
}

static void MDFConfirm(NSString *title, NSString *message, dispatch_block_t onConfirm) {
    UIViewController *top = MDFTopViewController();
    if (!top) { onConfirm(); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Like"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            (void)action;
            onConfirm();
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];
        [MDFTopViewController() presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Download helpers

static void MDFDownloadAndShare(NSURL *remoteURL) {
    if (!remoteURL) return;
    MDFLog(@"downloading %@", remoteURL.absoluteString);
    [[[NSURLSession sharedSession] downloadTaskWithURL:remoteURL
                                     completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        (void)response;
        if (!location) { MDFLog(@"download failed: %@", error); return; }
        NSString *name = remoteURL.lastPathComponent.length ? remoteURL.lastPathComponent : @"MooDfacebook-media";
        if (![name containsString:@"."]) name = [name stringByAppendingPathExtension:@"mp4"];
        NSURL *target = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        [[NSFileManager defaultManager] removeItemAtURL:target error:NULL];
        NSError *moveError = nil;
        if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:target error:&moveError]) {
            MDFLog(@"move failed: %@", moveError);
            return;
        }
        MDFPresentShare(target);
    }] resume];
}

static void MDFSaveAndShareImage(UIImage *image) {
    if (!image) return;
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"MooDfacebook-%@.png", NSUUID.UUID.UUIDString]];
    if (![data writeToFile:path atomically:YES]) return;
    MDFPresentShare([NSURL fileURLWithPath:path]);
}

static void MDFEnsureLongPress(UIView *host) {
    if (!host) return;
    NSMutableArray *recognizers = [host.gestureRecognizers mutableCopy] ?: [NSMutableArray array];
    for (UIGestureRecognizer *recognizer in recognizers) {
        if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) return;
    }
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:host action:@selector(mdf_handleLongPress:)];
    press.minimumPressDuration = 0.6;
    press.cancelsTouchesInView = NO;
    [host addGestureRecognizer:press];
}

#pragma mark - Incognito stories (no seen receipt)

static void MDFNoopIMP(void) {}

static void MDFDisableStorySeenTracking(void) {
    if (!MDFPref(@"incognitoStories", YES)) return;
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        const char *className = class_getName(cls);
        if (!className || !strstr(className, "Story")) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        for (unsigned int j = 0; j < methodCount; j++) {
            const char *selectorName = sel_getName(method_getName(methods[j]));
            if (!selectorName) continue;
            if (strstr(selectorName, "markStorySeen") ||
                strstr(selectorName, "markSeen") ||
                strstr(selectorName, "setStorySeen") ||
                strstr(selectorName, "reportSeen")) {
                method_setImplementation(methods[j], (IMP)MDFNoopIMP);
                MDFLog(@"disabled %s -%s", className, selectorName);
            }
        }
        free(methods);
    }
    free(classes);
}

#pragma mark - Hooks

%group MDFCore

// 4. Confirm post like — intercept like/reaction actions on any UIControl.
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (MDFPref(@"enabled", YES) && MDFPref(@"confirmLike", YES)) {
        NSString *actionName = NSStringFromSelector(action);
        NSString *haystack = [NSString stringWithFormat:@"%@ %@", actionName ?: @"", self.accessibilityLabel ?: @""].lowercaseString;
        BOOL looksLikeLike = [haystack containsString:@"like"] ||
                             [haystack containsString:@"react"] ||
                             [haystack containsString:@"أعجبني"] ||
                             [haystack containsString:@"إعجاب"];
        NSMutableDictionary *thread = [NSThread currentThread].threadDictionary;
        if (looksLikeLike && !thread[kMDFConfirmFlag]) {
            thread[kMDFConfirmFlag] = @YES;
            __weak UIControl *weakSelf = self;
            MDFConfirm(@"Confirm like", @"Do you want to like this post?", ^{
                UIControl *strongSelf = weakSelf;
                // The flag stays set while the like action re-enters this hook, so the
                // re-entrant call falls through to %orig instead of prompting again.
                if (strongSelf) [strongSelf sendAction:action to:target forEvent:event];
                [thread removeObjectForKey:kMDFConfirmFlag];
            });
            return;
        }
    }
    %orig;
}
%end

// 1 + 2 + 3 — feed cells: sponsored, suggested, People you may know, Reels shelf.
// Facebook builds its feed with UICollectionView, so hooking the base cell class
// covers the feed regardless of the internal cell subclass names.
%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (!MDFPref(@"enabled", YES)) return;

    if (MDFPref(@"hideAds", YES) && MDFViewMatchesMarkers(self, MDFAdMarkers())) {
        MDFLog(@"hiding sponsored cell");
        self.hidden = YES;
    }
    if (MDFPref(@"hidePYMK", YES) && MDFViewMatchesMarkers(self, MDFPYMKMarkers())) {
        MDFLog(@"hiding PYMK / suggested cell");
        self.hidden = YES;
    }
    if (MDFPref(@"hideReelsCarousel", YES) && MDFViewMatchesMarkers(self, MDFReelsMarkers())) {
        MDFLog(@"hiding reels shelf cell");
        self.hidden = YES;
    }
    if (MDFPref(@"downloadMedia", YES)) MDFEnsureLongPress(self);
}
- (void)mdf_handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    if (!MDFPref(@"enabled", YES)) return;
    UIView *host = recognizer.view;
    NSURL *video = MDFVideoURLInView(host);
    if (video) { MDFDownloadAndShare(video); return; }
    UIImage *image = MDFImageInView(host);
    if (image) MDFSaveAndShareImage(image);
}
%end

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (!MDFPref(@"enabled", YES)) return;
    if (MDFPref(@"hideAds", YES) && MDFViewMatchesMarkers(self, MDFAdMarkers())) self.hidden = YES;
    if (MDFPref(@"hidePYMK", YES) && MDFViewMatchesMarkers(self, MDFPYMKMarkers())) self.hidden = YES;
    if (MDFPref(@"downloadMedia", YES)) MDFEnsureLongPress(self);
}
- (void)mdf_handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    UIView *host = recognizer.view;
    NSURL *video = MDFVideoURLInView(host);
    if (video) { MDFDownloadAndShare(video); return; }
    UIImage *image = MDFImageInView(host);
    if (image) MDFSaveAndShareImage(image);
}
%end

// 3 — dedicated Reels shelf view, when present.
%hook FBReelsShelfView
- (void)layoutSubviews {
    %orig;
    if (MDFPref(@"enabled", YES) && MDFPref(@"hideReelsCarousel", YES)) self.hidden = YES;
}
%end

// 5 + 6 — Reels viewer: download on long press, hide the action overlay.
%hook FBReelsViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!MDFPref(@"enabled", YES)) return;
    if (MDFPref(@"downloadReels", YES)) MDFEnsureLongPress(self.view);
    if (MDFPref(@"hideReelsOverlay", YES)) MDFHideOverlayInView(self.view);
}
- (void)mdf_handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    NSURL *video = MDFVideoURLInView(recognizer.view);
    if (video) MDFDownloadAndShare(video);
}
%end

%hook FBReelsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (MDFPref(@"enabled", YES) && MDFPref(@"hideReelsOverlay", YES)) MDFHideOverlayInView(self.view);
}
%end

// 7 — Stories: download on long press, incognito viewing.
%hook FBStoryViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!MDFPref(@"enabled", YES)) return;
    if (MDFPref(@"downloadStories", YES)) MDFEnsureLongPress(self.view);
}
- (void)mdf_handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    UIView *host = recognizer.view;
    NSURL *video = MDFVideoURLInView(host);
    if (video) { MDFDownloadAndShare(video); return; }
    UIImage *image = MDFImageInView(host);
    if (image) MDFSaveAndShareImage(image);
}
%end

// 5 — keep track of the most recently played video so long press can grab it.
%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    AVAsset *asset = item.asset;
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        MDFLog(@"playing %@", ((AVURLAsset *)asset).URL.absoluteString);
    }
}
%end

%end // MDFCore

%ctor {
    %init(MDFCore);
    // Scanning every loaded class is cheap but not free, and Facebook loads a very
    // large number of them, so keep it off the launch-critical path.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        MDFDisableStorySeenTracking();
    });
    MDFLog(@"MooDfacebook loaded");
}
