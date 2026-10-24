#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

#pragma mark - Prefs

static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist";

static BOOL gEnabled = YES;
static BOOL gRemoveAds = YES;
static BOOL gRemovePYMK = YES;
static BOOL gRemoveReelsCarousel = YES;
static BOOL gConfirmPostLike = YES;
static BOOL gDownloadMedia = YES;
static BOOL gReelsDownloadBtn = YES;
static BOOL gReelsHideOverlay = NO;
static BOOL gConfirmReelsLike = YES;
static BOOL gReelsLongPressDL = YES;
static BOOL gStoriesDownload = YES;
static BOOL gStoriesAnon = YES;
static BOOL gStoriesManualSeen = YES;
static BOOL gStoriesNoAuto = YES;

static void MFSavePrefs(void);
static void MFLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!d) return;
    id v;
    #define R(k, g) do { v = d[@#k]; if (v) g = [v boolValue]; } while(0)
    R(enabled, gEnabled);
    R(removeAds, gRemoveAds);
    R(removePYMK, gRemovePYMK);
    R(removeReelsCarousel, gRemoveReelsCarousel);
    R(confirmPostLike, gConfirmPostLike);
    R(downloadMedia, gDownloadMedia);
    R(reelsDownloadBtn, gReelsDownloadBtn);
    R(reelsHideOverlay, gReelsHideOverlay);
    R(confirmReelsLike, gConfirmReelsLike);
    R(reelsLongPressDL, gReelsLongPressDL);
    R(storiesDownload, gStoriesDownload);
    R(storiesAnon, gStoriesAnon);
    R(storiesManualSeen, gStoriesManualSeen);
    R(storiesNoAuto, gStoriesNoAuto);
    #undef R
}

static void MFSavePrefs(void) {
    NSDictionary *d = @{
        @"enabled": @(gEnabled),
        @"removeAds": @(gRemoveAds),
        @"removePYMK": @(gRemovePYMK),
        @"removeReelsCarousel": @(gRemoveReelsCarousel),
        @"confirmPostLike": @(gConfirmPostLike),
        @"downloadMedia": @(gDownloadMedia),
        @"reelsDownloadBtn": @(gReelsDownloadBtn),
        @"reelsHideOverlay": @(gReelsHideOverlay),
        @"confirmReelsLike": @(gConfirmReelsLike),
        @"reelsLongPressDL": @(gReelsLongPressDL),
        @"storiesDownload": @(gStoriesDownload),
        @"storiesAnon": @(gStoriesAnon),
        @"storiesManualSeen": @(gStoriesManualSeen),
        @"storiesNoAuto": @(gStoriesNoAuto),
    };
    [d writeToFile:kPrefsPath atomically:YES];
}

#pragma mark - Helpers

static NSArray<UIWindow *> *MFWindows(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]])
            [a addObjectsFromArray:((UIWindowScene *)s).windows];
    }
    return a;
}

static UIWindow *MFKeyWindow(void) {
    for (UIWindow *w in MFWindows()) if (w.isKeyWindow) return w;
    return MFWindows().firstObject;
}

static UIViewController *MFTopVC(void) {
    UIViewController *vc = MFKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static BOOL MFTextMatch(NSString *s, NSArray<NSString *> *needles) {
    if (!s.length) return NO;
    NSString *l = s.lowercaseString;
    for (NSString *n in needles) {
        if ([l containsString:n.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL MFIsAdOrSuggestedText(NSString *s) {
    if (gRemoveAds && MFTextMatch(s, @[@