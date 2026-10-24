// MooDfacebook - Facebook tweak (iOS 15+, arm64e, RootHide)
// Facebook internal classes are obfuscated and change between versions,
// so these hooks use public UIKit / Foundation classes and check at runtime.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#define MDF_DOMAIN @"com.mody.moodfacebook"

static NSUserDefaults *MDFDefaults(void) {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[NSUserDefaults alloc] initWithSuiteName:MDF_DOMAIN]; });
    return d;
}

static BOOL MDFOn(NSString *key) {
    id v = [MDFDefaults() objectForKey:key];
    return v ? [v boolValue] : YES;
}

#define kNoAds          @"noAds"
#define kNoReelsAutoNext @"noReelsAutoNext"
#define kReelsNoMute    @"reelsKeepSound"
#define kStealthStories @"stealthStories"
#define kStealthMessages @"stealthMessages"
#define kNoTyping       @"noTyping"

// ------------------------------------------------------------
// Ads: hide feed / reels cells marked as sponsored
// ------------------------------------------------------------

static NSArray<NSString *> *MDFSponsoredWords(void) {
    return @[@"Sponsored", @"\u0645\u0645\u0648\u0644", @"Sponsoris", @"Patrocinado", @"Gesponsert", @"Reklam"];
}

static BOOL MDFTextIsSponsored(NSString *s) {
    if (s.length == 0 || s.length > 400) return NO;
    for (NSString *w in MDFSponsoredWords()) {
        if ([s rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL MDFViewIsSponsored(UIView *v, int depth) {
    if (!v || depth > 6) return NO;
    if (MDFTextIsSponsored(v.accessibilityLabel) || MDFTextIsSponsored(v.accessibilityIdentifier)) return YES;
    if ([v isKindOfClass:[UILabel class]] && MDFTextIsSponsored(((UILabel *)v).text)) return YES;
    for (UIView *sub in v.subviews) {
        if (MDFViewIsSponsored(sub, depth + 1)) return YES;
    }
    return NO;
}

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (!MDFOn(kNoAds)) return;
    BOOL ad = MDFViewIsSponsored(self.contentView, 0);
    if (ad) {
        self.hidden = YES;
        self.contentView.alpha = 0;
    } else if (self.hidden && self.contentView.alpha == 0) {
        self.hidden = NO;
        self.contentView.alpha = 1;
    }
}
%end

// Block known ad / tracking endpoints at the network level
static BOOL MDFIsAdURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString;
    if (!s) return NO;
    for (NSString *p in @[@"/ads/", @"an.facebook.com", @"adsmanager", @"/ad_request", @"ads_interference"]) {
        if ([s containsString:p]) return YES;
    }
    return NO;
}

// ------------------------------------------------------------
// Stealth: drop "seen" / "read" / typing requests
// ------------------------------------------------------------

static BOOL MDFShouldBlockRequest(NSURLRequest *req) {
    if (MDFOn(kNoAds) && MDFIsAdURL(req.URL)) return YES;
    NSData *body = req.HTTPBody;
    if (body.length == 0 || body.length > 200000) return NO;
    NSString *b = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!b) return NO;
    if (MDFOn(kStealthStories)) {
        for (NSString *k in @[@"StorySeen", @"storiesUpdateSeenState", @"story_seen", @"StoriesSeenMutation", @"bucket_seen"]) {
            if ([b containsString:k]) return YES;
        }
    }
    if (MDFOn(kStealthMessages)) {
        for (NSString *k in @[@"MarkThreadRead", @"mark_read", @"markThreadAsRead", @"read_receipt"]) {
            if ([b containsString:k]) return YES;
        }
    }
    if (MDFOn(kNoTyping)) {
        for (NSString *k in @[@"typing_indicator", @"TypingIndicator", @"send_typing"]) {
            if ([b containsString:k]) return YES;
        }
    }
    return NO;
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (MDFShouldBlockRequest(request)) {
        NSMutableURLRequest *r = [request mutableCopy];
        r.URL = [NSURL URLWithString:@"https://127.0.0.1:1/mdf-blocked"];
        r.HTTPBody = nil;
        return %orig(r, completionHandler);
    }
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (MDFShouldBlockRequest(request)) {
        NSMutableURLRequest *r = [request mutableCopy];
        r.URL = [NSURL URLWithString:@"https://127.0.0.1:1/mdf-blocked"];
        r.HTTPBody = nil;
        return %orig(r);
    }
    return %orig;
}
%end

// ------------------------------------------------------------
// Reels / Stories: no auto-advance, keep sound
// ------------------------------------------------------------

%hook AVPlayer
- (void)setMuted:(BOOL)muted {
    if (MDFOn(kReelsNoMute) && muted) { %orig(NO); return; }
    %orig;
}
%end

%hook AVPlayerItem
- (void)setActionAtItemEnd:(NSInteger)action { %orig; }
%end

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)obj userInfo:(NSDictionary *)info {
    // When a reel/story video ends, swallow the end notification so the app
    // does not jump to the next item; loop the current item instead.
    if (MDFOn(kNoReelsAutoNext) && [name isEqualToString:AVPlayerItemDidPlayToEndTimeNotification] && [obj isKindOfClass:[AVPlayerItem class]]) {
        [(AVPlayerItem *)obj seekToTime:kCMTimeZero completionHandler:nil];
        return;
    }
    %orig;
}
%end

// ------------------------------------------------------------
// Settings panel: long-press any bottom tab bar item
// ------------------------------------------------------------

@interface MDFSettingsController : UITableViewController
@end

@implementation MDFSettingsController {
    NSArray<NSArray *> *_rows;
    NSArray<NSString *> *_sections;
}
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"MooDfacebook";
        _sections = @[@"\u0627\u0644\u0625\u0639\u0644\u0627\u0646\u0627\u062a", @"\u0627\u0644\u0631\u064a\u0644\u0632 \u0648\u0627\u0644\u0642\u0635\u0635", @"\u0627\u0644\u0645\u0634\u0627\u0647\u062f\u0629 \u0627\u0644\u062e\u0641\u064a\u0629"];
        _rows = @[
            @[@[kNoAds, @"\u0625\u0632\u0627\u0644\u0629 \u0627\u0644\u0625\u0639\u0644\u0627\u0646\u0627\u062a"]],
            @[@[kNoReelsAutoNext, @"\u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0627\u0644\u062a\u0644\u0642\u0627\u0626\u064a"], @[kReelsNoMute, @"\u0625\u0628\u0642\u0627\u0621 \u0627\u0644\u0635\u0648\u062a \u0645\u0641\u0639\u0644\u0627\u064b"]],
            @[@[kStealthStories, @"\u0625\u062e\u0641\u0627\u0621 \u0645\u0634\u0627\u0647\u062f\u0629 \u0627\u0644\u0642\u0635\u0635"], @[kStealthMessages, @"\u0625\u062e\u0641\u0627\u0621 \u0642\u0631\u0627\u0621\u0629 \u0627\u0644\u0631\u0633\u0627\u0626\u0644"], @[kNoTyping, @"\u0625\u062e\u0641\u0627\u0621 \u062c\u0627\u0631\u064d \u0627\u0644\u0643\u062a\u0627\u0628\u0629"]]
        ];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(mdf_close)];
}
- (void)mdf_close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return _sections.count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return _sections[s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return s == (NSInteger)_sections.count - 1 ? @"\u0623\u0639\u062f \u062a\u0634\u063a\u064a\u0644 \u0641\u064a\u0633\u0628\u0648\u0643 \u0644\u062a\u0637\u0628\u064a\u0642 \u0627\u0644\u062a\u063a\u064a\u064a\u0631\u0627\u062a. by Mody" : nil;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _rows[s].count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *row = _rows[ip.section][ip.row];
    c.textLabel.text = row[1];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    sw.on = MDFOn(row[0]);
    sw.tag = ip.section * 100 + ip.row;
    [sw addTarget:self action:@selector(mdf_toggle:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}
- (void)mdf_toggle:(UISwitch *)sw {
    NSArray *row = _rows[sw.tag / 100][sw.tag % 100];
    [MDFDefaults() setBool:sw.on forKey:row[0]];
}
@end

@interface UITabBar (MDF)
- (void)mdf_longPress:(UILongPressGestureRecognizer *)g;
@end

static UIViewController *MDFTopController(void) {
    UIWindow *win = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) { if (w.isKeyWindow) { win = w; break; } }
    }
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    static const char kMDFKey = 0;
    if (objc_getAssociatedObject(self, &kMDFKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mdf_longPress:)];
    lp.minimumPressDuration = 0.8;
    lp.cancelsTouchesInView = NO;
    [self addGestureRecognizer:lp];
    objc_setAssociatedObject(self, &kMDFKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (void)mdf_longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = MDFTopController();
    if (!top || [top isKindOfClass:[UINavigationController class]] && [((UINavigationController *)top).topViewController isKindOfClass:[MDFSettingsController class]]) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[MDFSettingsController new]];
    nav.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium].impactOccurred;
    [top presentViewController:nav animated:YES completion:nil];
}
%end

%ctor {
    %init;
}
