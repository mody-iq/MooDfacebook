#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString * const kPrefsID = @"com.modyiq.moodfacebook";
static NSString * const kPrefsFile = @"/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist";

static BOOL gEnabled = YES;
static BOOL gHideAds = YES;
static BOOL gHideSuggested = YES;
static BOOL gHideStories = NO;
static BOOL gHideReelsShelf = NO;
static BOOL gForceDark = NO;

static void MFLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsFile];
    if (!d) {
        // defaults
        gEnabled = YES;
        gHideAds = YES;
        gHideSuggested = YES;
        gHideStories = NO;
        gHideReelsShelf = NO;
        gForceDark = NO;
        return;
    }
    id v;
    v = d[@"enabled"];        gEnabled = v ? [v boolValue] : YES;
    v = d[@"hideAds"];        gHideAds = v ? [v boolValue] : YES;
    v = d[@"hideSuggested"];  gHideSuggested = v ? [v boolValue] : YES;
    v = d[@"hideStories"];    gHideStories = v ? [v boolValue] : NO;
    v = d[@"hideReelsShelf"]; gHideReelsShelf = v ? [v boolValue] : NO;
    v = d[@"forceDark"];      gForceDark = v ? [v boolValue] : NO;
}

static BOOL MFLooksLikeAdText(NSString *s) {
    if (s.length < 3) return NO;
    NSString *l = s.lowercaseString;
    // Sponsored / ads
    if (gHideAds) {
        if ([l containsString:@"sponsored"]) return YES;
        if ([l containsString:@"مموّل"] || [l containsString:@"ممول"]) return YES;
        if ([l containsString:@"annonce sponsorisée"]) return YES;
        if ([l containsString:@"gesponsert"]) return YES;
        if ([l containsString:@"sponsorizzato"]) return YES;
        if ([l containsString:@"patrocinado"]) return YES;
        if ([l containsString:@"reklam"]) return YES;
    }
    // Suggested
    if (gHideSuggested) {
        if ([l containsString:@"suggested for you"]) return YES;
        if ([l containsString:@"مقترح لك"]) return YES;
        if ([l containsString:@"people you may know"]) return YES;
        if ([l containsString:@"أشخاص قد تعرفهم"]) return YES;
        if ([l containsString:@"suggested pages"]) return YES;
        if ([l containsString:@"join group"]) return YES;
        if ([l containsString:@"suggested groups"]) return YES;
    }
    // Reels shelf title
    if (gHideReelsShelf) {
        if ([l isEqualToString:@"reels"] || [l hasPrefix:@"reels"]) return YES;
        if ([l containsString:@"ريلز"]) return YES;
    }
    return NO;
}

static BOOL MFTreeHasAdLabel(UIView *view, int depth) {
    if (!view || depth > 10) return NO;
    if ([view isKindOfClass:[UILabel class]]) {
        if (MFLooksLikeAdText(((UILabel *)view).text)) return YES;
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        if (MFLooksLikeAdText([b titleForState:UIControlStateNormal])) return YES;
        if (b.titleLabel && MFLooksLikeAdText(b.titleLabel.text)) return YES;
    }
    @try {
        id at = [view valueForKey:@"attributedText"];
        if ([at isKindOfClass:[NSAttributedString class]] && MFLooksLikeAdText([at string])) return YES;
    } @catch (__unused NSException *e) {}
    for (UIView *sub in view.subviews) {
        if (MFTreeHasAdLabel(sub, depth + 1)) return YES;
    }
    return NO;
}

static void MFCollapseView(UIView *v) {
    if (!v || v.hidden) return;
    v.hidden = YES;
    v.alpha = 0;
    CGRect f = v.frame;
    if (f.size.height > 1) {
        f.size.height = 0;
        v.frame = f;
    }
}

%hook UICollectionViewCell

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (!(gHideAds || gHideSuggested || gHideReelsShelf)) return;
    if (self.bounds.size.height < 50) return;
    if (MFTreeHasAdLabel(self, 0)) {
        MFCollapseView(self);
        self.contentView.hidden = YES;
    }
}

%end

%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (!(gHideAds || gHideSuggested)) return;
    if (self.bounds.size.height < 40) return;
    if (MFTreeHasAdLabel(self, 0)) {
        MFCollapseView(self);
        self.contentView.hidden = YES;
    }
}

%end

%hook UICollectionView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled || !gHideStories) return;
    // Story tray: short, wide, near top
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;
    if (h > 50 && h < 140 && w > h * 1.8) {
        UIWindow *win = self.window;
        if (!win) return;
        CGRect r = [self convertRect:self.bounds toView:win];
        if (r.origin.y >= 0 && r.origin.y < 220) {
            MFCollapseView(self);
        }
    }
}

%end

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (gEnabled && gForceDark) {
        if (@available(iOS 13.0, *)) {
            self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            if (self.view) self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }
}

- (UIUserInterfaceStyle)overrideUserInterfaceStyle {
    if (gEnabled && gForceDark) {
        if (@available(iOS 13.0, *)) return UIUserInterfaceStyleDark;
    }
    return %orig;
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    if (gEnabled && gForceDark) {
        if (@available(iOS 13.0, *)) {
            self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }
}

%end

%ctor {
    MFLoadPrefs();

    int token = 0;
    notify_register_dispatch("com.modyiq.moodfacebook/ReloadPrefs",
        &token, dispatch_get_main_queue(), ^(__unused int t) {
        MFLoadPrefs();
        NSLog(@"[MooDfacebook] prefs reloaded");
    });

    NSLog(@"[MooDfacebook] v0.1.1 loaded en=%d ads=%d sug=%d stories=%d dark=%d",
          gEnabled, gHideAds, gHideSuggested, gHideStories, gForceDark);
}
