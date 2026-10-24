#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist";

static BOOL MFBool(NSString *key, BOOL def) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!d) return def;
    id v = d[key];
    if (!v) return def;
    return [v boolValue];
}

static BOOL MFEnabled(void) { return MFBool(@"enabled", YES); }
static BOOL MFHideAds(void) { return MFBool(@"hideAds", YES); }
static BOOL MFHideSuggested(void) { return MFBool(@"hideSuggested", YES); }
static BOOL MFForceDark(void) { return MFBool(@"forceDark", NO); }
static BOOL MFHideStories(void) { return MFBool(@"hideStories", NO); }

static BOOL MFStringLooksSponsored(NSString *s) {
    if (!s.length) return NO;
    NSString *l = s.lowercaseString;
    // EN / AR common markers
    if ([l containsString:@"sponsored"]) return YES;
    if ([l containsString:@"مموّل"] || [l containsString:@"ممول"]) return YES;
    if ([l containsString:@"annonce sponsorisée"]) return YES;
    if ([l containsString:@"gesponsert"]) return YES;
    if ([l containsString:@"sponsorizzato"]) return YES;
    if ([l containsString:@"patrocinado"]) return YES;
    if (MFHideSuggested()) {
        if ([l containsString:@"suggested for you"]) return YES;
        if ([l containsString:@"مقترح لك"]) return YES;
        if ([l containsString:@"people you may know"]) return YES;
        if ([l containsString:@"أشخاص قد تعرفهم"]) return YES;
    }
    return NO;
}

static BOOL MFViewTreeHasSponsoredLabel(UIView *view, int depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:[UILabel class]]) {
        if (MFStringLooksSponsored(((UILabel *)view).text)) return YES;
    }
    if ([view isKindOfClass:[UIButton class]]) {
        NSString *t = [(UIButton *)view titleForState:UIControlStateNormal];
        if (MFStringLooksSponsored(t)) return YES;
    }
    if ([view respondsToSelector:@selector(attributedText)]) {
        NSAttributedString *as = [view valueForKey:@"attributedText"];
        if ([as isKindOfClass:[NSAttributedString class]] && MFStringLooksSponsored(as.string)) return YES;
    }
    for (UIView *sub in view.subviews) {
        if (MFViewTreeHasSponsoredLabel(sub, depth + 1)) return YES;
    }
    return NO;
}

static void MFHideIfSponsoredCell(UIView *cell) {
    if (!MFEnabled() || !MFHideAds()) return;
    if (!cell) return;
    if (MFViewTreeHasSponsoredLabel(cell, 0)) {
        cell.hidden = YES;
        CGRect f = cell.frame;
        f.size.height = 0;
        cell.frame = f;
        cell.alpha = 0;
    }
}

// ---- UICollectionView cells (modern FB feed) ----
%hook UICollectionViewCell

- (void)layoutSubviews {
    %orig;
    if (!MFEnabled() || !MFHideAds()) return;
    // Only act on reasonably tall feed-like cells
    if (self.bounds.size.height < 80) return;
    MFHideIfSponsoredCell(self);
}

%end

// ---- UITableView cells (legacy / settings-like lists) ----
%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (!MFEnabled() || !MFHideAds()) return;
    if (self.bounds.size.height < 60) return;
    MFHideIfSponsoredCell(self);
}

%end

// ---- Forced dark mode ----
%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (MFEnabled() && MFForceDark()) {
        if (@available(iOS 13.0, *)) {
            self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    if (MFEnabled() && MFForceDark()) {
        if (@available(iOS 13.0, *)) {
            self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }
}

%end

// ---- Optional: hide story tray by zeroing short wide collection sections ----
%hook UICollectionView

- (void)layoutSubviews {
    %orig;
    if (!MFEnabled() || !MFHideStories()) return;
    // Heuristic: horizontal story-like layouts near top — hide if very short height
    if (self.bounds.size.height > 40 && self.bounds.size.height < 130 &&
        self.bounds.size.width > self.bounds.size.height * 2) {
        // Check if parent is near top of screen
        UIWindow *w = self.window;
        if (!w) return;
        CGRect r = [self convertRect:self.bounds toView:w];
        if (r.origin.y < 180) {
            self.hidden = YES;
            self.alpha = 0;
        }
    }
}

%end

%ctor {
    // Prefer jbroot path under RootHide when available
    #ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    // path already logical; RootHide redirects Preferences for tweaks as needed
    #endif
    NSLog(@"[MooDfacebook] v0.1.0 loaded (enabled=%d hideAds=%d dark=%d)",
          MFEnabled(), MFHideAds(), MFForceDark());
}
