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

#define kNoAds           @"noAds"
#define kNoReelsAutoNext @"noReelsAutoNext"
#define kReelsNoMute     @"reelsKeepSound"
#define kStealthStories  @"stealthStories"
#define kStealthMessages @"stealthMessages"
#define kNoTyping        @"noTyping"

// ---------------- Ads ----------------

static BOOL MDFTextIsSponsored(NSString *s) {
    if (s.length == 0 || s.length > 400) return NO;
    static NSArray<NSString *> *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ words = @[@"Sponsored", @"ممول", @"Sponsoris", @"Patrocinado", @"Gesponsert", @"Reklam"]; });
    for (NSString *w in words) {
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
    if (MDFViewIsSponsored(self.contentView, 0)) {
        self.hidden = YES;
        self.contentView.alpha = 0;
    } else if (self.hidden && self.contentView.alpha == 0) {
        self.hidden = NO;
        self.contentView.alpha = 1;
    }
}
%end

static BOOL MDFIsAdURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString;
    if (!s) return NO;
    for (NSString *p in @[@"/ads/", @"an.facebook.com", @"adsmanager", @"/ad_request", @"ads_interference"]) {
        if ([s containsString:p]) return YES;
    }
    return NO;
}

// ---------------- Stealth ----------------

static BOOL MDFBodyHas(NSString *b, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        if ([b containsString:k]) return YES;
    }
    return NO;
}

static BOOL MDFShouldBlockRequest(NSURLRequest *req) {
    if (MDFOn(kNoAds) && MDFIsAdURL(req.URL)) return YES;
    NSData *body = req.HTTPBody;
    if (body.length == 0 || body.length > 200000) return NO;
    NSString *b = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!b) return NO;
    if (MDFOn(kStealthStories) && MDFBodyHas(b, @[@"StorySeen", @"storiesUpdateSeenState", @"story_seen", @"StoriesSeenMutation", @"bucket_seen"])) return YES;
    if (MDFOn(kStealthMessages) && MDFBodyHas(b, @[@"MarkThreadRead", @"mark_read", @"markThreadAsRead", @"read_receipt"])) return YES;
    if (MDFOn(kNoTyping) && MDFBodyHas(b, @[@"typing_indicator", @"TypingIndicator", @"send_typing"])) return YES;
    return NO;
}

static NSURLRequest *MDFFilterRequest(NSURLRequest *request) {
    if (!MDFShouldBlockRequest(request)) return request;
    NSMutableURLRequest *r = [request mutableCopy];
    r.URL = [NSURL URLWithString:@"https://127.0.0.1:1/mdf-blocked"];
    r.HTTPBody = nil;
    return r;
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completionHandler {
    request = MDFFilterRequest(request);
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    request = MDFFilterRequest(request);
    return %orig;
}
%end

// ---------------- Reels / Stories ----------------

%hook AVPlayer
- (void)setMuted:(BOOL)muted {
    if (MDFOn(kReelsNoMute)) {
        muted = NO;
    }
    %orig;
}
%end

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)obj userInfo:(NSDictionary *)info {
    if (MDFOn(kNoReelsAutoNext) && [name isEqualToString:AVPlayerItemDidPlayToEndTimeNotification] && [obj isKindOfClass:[AVPlayerItem class]]) {
        [(AVPlayerItem *)obj seekToTime:kCMTimeZero completionHandler:nil];
        return;
    }
    %orig;
}
%end

// ---------------- Settings ----------------

@interface MDFSettingsController : UITableViewController
@end

@implementation MDFSettingsController {
    NSArray<NSArray *> *_rows;
    NSArray<NSString *> *_sections;
}
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"MooDfacebook";
        _sections = @[@"الإعلانات", @"الريلز والقصص", @"المشاهدة الخفية"];
        _rows = @[
            @[@[kNoAds, @"إزالة الإعلانات"]],
            @[@[kNoReelsAutoNext, @"إيقاف الانتقال التلقائي"], @[kReelsNoMute, @"إبقاء الصوت مفعلاً"]],
            @[@[kStealthStories, @"إخفاء مشاهدة القصص"], @[kStealthMessages, @"إخفاء قراءة الرسائل"], @[kNoTyping, @"إخفاء جارٍ الكتابة"]]
        ];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(mdf_close)];
}
- (void)mdf_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    return _sections.count;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return _sections[s];
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == (NSInteger)_sections.count - 1) return @"أعد تشغيل فيسبوك لتطبيق التغييرات. by Mody";
    return nil;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return _rows[s].count;
}
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

static UIViewController *MDFTopController(void) {
    UIWindow *win = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
    }
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static const char kMDFGestureKey = 0;

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (objc_getAssociatedObject(self, &kMDFGestureKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mdf_longPress:)];
    lp.minimumPressDuration = 0.8;
    lp.cancelsTouchesInView = NO;
    [self addGestureRecognizer:lp];
    objc_setAssociatedObject(self, &kMDFGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)mdf_longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = MDFTopController();
    if (!top) return;
    if ([top isKindOfClass:[UINavigationController class]]) {
        UIViewController *inner = ((UINavigationController *)top).topViewController;
        if ([inner isKindOfClass:[MDFSettingsController class]]) return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[MDFSettingsController new]];
    nav.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [fb impactOccurred];
    [top presentViewController:nav animated:YES completion:nil];
}
%end

%ctor {
    %init;
}
