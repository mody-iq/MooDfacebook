// Discovery.m — MooDfacebook discovery logger v2 (temporary).
// LOG  button: tap = share log, long press = clear.
// DEEP button: tap = inspect video player / Snacks / selectors, then share.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#include <string.h>
#include <strings.h>

static NSMutableArray<NSString *> *gDLines;
static NSMutableSet<NSString *> *gDSeen;
static NSMutableArray<NSString *> *gDDeep;
static NSMutableSet<NSString *> *gDDeepSeen;
static NSUInteger gDCellLines = 0;
static NSUInteger gDMarkLines = 0;
static NSUInteger gDCtrlLines = 0;
static NSUInteger gDPlayerLines = 0;
static NSUInteger gDNodes = 0;
static UIWindow *gDWindow = nil;

#pragma mark - Basic helpers

static NSString *MDDClip(NSString *s, NSUInteger n) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    NSString *t = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (t.length > n) return [[t substringToIndex:n] stringByAppendingString:@"..."];
    return t;
}

static BOOL MDDAdd(NSString *line) {
    if (!line.length) return NO;
    if (!gDLines) {
        gDLines = [NSMutableArray array];
        gDSeen = [NSMutableSet set];
    }
    if ([gDSeen containsObject:line] || gDLines.count >= 900) return NO;
    [gDSeen addObject:line];
    [gDLines addObject:line];
    return YES;
}

static BOOL MDDDeepAdd(NSString *line) {
    if (!line.length) return NO;
    if (!gDDeep) {
        gDDeep = [NSMutableArray array];
        gDDeepSeen = [NSMutableSet set];
    }
    if ([gDDeepSeen containsObject:line] || gDDeep.count >= 1000) return NO;
    [gDDeepSeen addObject:line];
    [gDDeep addObject:line];
    return YES;
}

static BOOL MDDContainsAny(NSString *lower, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        if ([lower containsString:key]) return YES;
    }
    return NO;
}

static NSString *MDDURL(NSURL *u) {
    if (!u) return @"(nil)";
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    c.query = nil;
    c.fragment = nil;
    NSString *s = c.string ?: u.scheme;
    return MDDClip(s, 200);
}

static NSString *MDDIdPattern(NSString *ident) {
    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{4,}" options:0 error:NULL];
    });
    NSString *s = [regex stringByReplacingMatchesInString:ident options:0
                                                    range:NSMakeRange(0, ident.length)
                                             withTemplate:@"#"];
    return MDDClip(s, 60);
}

static NSString *MDDChain(UIView *v, int hops) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *current = v;
    int n = 0;
    while (current && n < hops) {
        NSString *name = NSStringFromClass([current class]);
        NSString *ident = current.accessibilityIdentifier;
        if ([ident isKindOfClass:[NSString class]] && ident.length) {
            name = [NSString stringWithFormat:@"%@{%@}", name, MDDIdPattern(ident)];
        }
        [parts addObject:name];
        current = current.superview;
        n++;
    }
    return [parts componentsJoinedByString:@" < "];
}

#pragma mark - Passive scan (LOG)

static BOOL MDDIsMarker(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length || text.length > 80) return NO;
    NSString *lower = text.lowercaseString;
    NSArray<NSString *> *keys = @[@"sponsored", @"suggested for you", @"people you may know",
                                  @"reels", @"short videos", @"ممول", @"مقترح",
                                  @"أشخاص قد تعرفهم", @"إعلان", @"advertis"];
    return MDDContainsAny(lower, keys);
}

static void MDDCollectSig(UIView *v, int depth, NSMutableArray<NSString *> *ids,
                          NSMutableArray<NSString *> *classes, int *count) {
    if (!v || depth > 18 || *count > 900) return;
    (*count)++;
    NSString *ident = v.accessibilityIdentifier;
    if ([ident isKindOfClass:[NSString class]] && ident.length && ![ident hasPrefix:@"mdf."]) {
        NSString *pattern = MDDIdPattern(ident);
        if (![ids containsObject:pattern] && ids.count < 30) [ids addObject:pattern];
    }
    NSString *className = NSStringFromClass([v class]);
    NSArray<NSString *> *adKeys = @[@"sponsor", @"promot", @"advert", @"boost", @"brandedcontent",
                                    @"paidpartner", @"adunit", @"adsstory", @"ctabutton"];
    if (MDDContainsAny(className.lowercaseString, adKeys) &&
        ![classes containsObject:className] && classes.count < 12) {
        [classes addObject:className];
    }
    for (UIView *sub in v.subviews) MDDCollectSig(sub, depth + 1, ids, classes, count);
}

static void MDDWalk(UIView *v, CGRect screen, int depth) {
    if (!v || depth > 45 || gDNodes > 6000 || v.hidden) return;
    gDNodes++;
    NSString *cls = NSStringFromClass([v class]);
    NSString *label = v.accessibilityLabel;

    // Marker words: log the full ancestor chain.
    NSString *text = nil;
    if ([v isKindOfClass:[UILabel class]]) text = ((UILabel *)v).text;
    NSString *hit = MDDIsMarker(label) ? label : (MDDIsMarker(text) ? text : nil);
    if (hit && gDMarkLines < 100) {
        NSString *line = [NSString stringWithFormat:@"MARK \"%@\" in %@ | chain: %@",
                          MDDClip(hit, 40), cls, MDDChain(v, 12)];
        if (MDDAdd(line)) gDMarkLines++;
    }

    // Visible feed cells: one signature line per distinct kind of cell.
    if ([v isKindOfClass:[UICollectionViewCell class]] || [v isKindOfClass:[UITableViewCell class]]) {
        CGRect f = [v convertRect:v.bounds toView:nil];
        if (CGRectIntersectsRect(f, screen) && gDCellLines < 150) {
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            NSMutableArray<NSString *> *classes = [NSMutableArray array];
            int count = 0;
            MDDCollectSig(v, 0, ids, classes, &count);
            NSString *line = [NSString stringWithFormat:@"SIG %@ in %@ | ids=[%@] | cls=[%@]",
                              cls, MDDChain(v.superview, 3),
                              [ids componentsJoinedByString:@", "],
                              [classes componentsJoinedByString:@", "]];
            if (MDDAdd(line)) gDCellLines++;
        }
    }

    // Video layers.
    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:v.layer];
    if (v.layer.sublayers) [layers addObjectsFromArray:v.layer.sublayers];
    for (CALayer *layer in layers) {
        if (gDPlayerLines >= 30) break;
        if ([layer isKindOfClass:[AVPlayerLayer class]]) {
            AVAsset *asset = ((AVPlayerLayer *)layer).player.currentItem.asset;
            NSString *url = @"(no asset)";
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                url = MDDURL(((AVURLAsset *)asset).URL);
            } else if (asset) {
                url = [NSString stringWithFormat:@"(%@)", NSStringFromClass([asset class])];
            }
            NSString *line = [NSString stringWithFormat:@"PLAYER host=%@ url=%@ chain: %@",
                              cls, url, MDDChain(v, 8)];
            if (MDDAdd(line)) gDPlayerLines++;
        } else if ([layer isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
            NSString *line = [NSString stringWithFormat:@"SBLAYER host=%@ chain: %@",
                              cls, MDDChain(v, 8)];
            if (MDDAdd(line)) gDPlayerLines++;
        }
    }

    // Controls that look like Like / reaction buttons.
    if ([v isKindOfClass:[UIControl class]] && gDCtrlLines < 40) {
        NSString *lowLabel = label.lowercaseString;
        NSString *lowClass = cls.lowercaseString;
        if ([lowLabel containsString:@"like"] || [lowLabel containsString:@"إعجاب"] ||
            [lowLabel containsString:@"أعجبني"] || [lowClass containsString:@"like"]) {
            UIControl *control = (UIControl *)v;
            NSMutableArray<NSString *> *acts = [NSMutableArray array];
            for (id t in control.allTargets) {
                id target = (t == [NSNull null]) ? nil : t;
                NSArray<NSString *> *names =
                    [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
                for (NSString *name in names ?: @[]) {
                    [acts addObject:[NSString stringWithFormat:@"%@.%@",
                                     target ? NSStringFromClass([target class]) : @"nil", name]];
                }
            }
            NSString *line = [NSString stringWithFormat:@"CTRL %@ label=%@ actions=[%@] chain: %@",
                              cls, MDDClip(label, 40), [acts componentsJoinedByString:@", "],
                              MDDChain(v.superview, 5)];
            if (MDDAdd(line)) gDCtrlLines++;
        }
    }

    for (UIView *sub in v.subviews) MDDWalk(sub, screen, depth + 1);
}

static void MDDVC(UIViewController *vc, int depth) {
    if (!vc || depth > 10) return;
    MDDAdd([NSString stringWithFormat:@"VC %d %@", depth, NSStringFromClass([vc class])]);
    for (UIViewController *child in vc.childViewControllers) MDDVC(child, depth + 1);
    if (vc.presentedViewController) MDDVC(vc.presentedViewController, depth + 1);
}

static void MDDScan(void) {
    @try {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window == gDWindow || window.hidden) continue;
                gDNodes = 0;
                MDDVC(window.rootViewController, 0);
                MDDWalk(window, window.bounds, 0);
            }
        }
    } @catch (NSException *exception) {
        MDDAdd([NSString stringWithFormat:@"EXC %@", exception.reason]);
    }
}

#pragma mark - Deep scan (DEEP)

static BOOL MDDLooksLikeMedia(NSString *s) {
    if (s.length == 0 || s.length > 1500) return NO;
    NSString *lower = s.lowercaseString;
    return MDDContainsAny(lower, @[@"http", @"fbcdn", @".mp4", @".m3u8", @".mpd"]);
}

static NSString *MDDMediaString(NSString *s) {
    NSURL *u = [NSURL URLWithString:s];
    if (u.scheme.length && u.host.length) return MDDURL(u);
    return MDDClip(s, 200);
}

static BOOL MDDSkipClassName(NSString *name) {
    NSArray<NSString *> *prefixes = @[@"UI", @"NS", @"CA", @"_", @"OS_", @"AV", @"WK", @"CK", @"CF"];
    for (NSString *prefix in prefixes) {
        if ([name hasPrefix:prefix]) return YES;
    }
    return NO;
}

static void MDDIvarScan(id obj, NSString *path, int depth, NSMutableSet<NSValue *> *visited);

static void MDDScanValue(id value, NSString *path, int depth, NSMutableSet<NSValue *> *visited) {
    if (!value) return;
    if ([value isKindOfClass:[NSURL class]]) {
        MDDDeepAdd([NSString stringWithFormat:@"IV %@ = URL %@", path, MDDURL(value)]);
        return;
    }
    if ([value isKindOfClass:[NSString class]]) {
        if (MDDLooksLikeMedia(value)) {
            MDDDeepAdd([NSString stringWithFormat:@"IV %@ = STR %@", path, MDDMediaString(value)]);
        }
        return;
    }
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
        NSUInteger i = 0;
        for (id item in value) {
            if (i >= 12) break;
            MDDScanValue(item, [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i], depth, visited);
            i++;
        }
        return;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSUInteger i = 0;
        for (id key in value) {
            if (i >= 12) break;
            id item = ((NSDictionary *)value)[key];
            MDDScanValue(item, [NSString stringWithFormat:@"%@[%@]", path, MDDClip([key description], 24)],
                         depth, visited);
            i++;
        }
        return;
    }
    NSString *className = NSStringFromClass([value class]);
    if (depth >= 2 || MDDSkipClassName(className)) return;
    MDDDeepAdd([NSString stringWithFormat:@"IV %@ : %@", path, className]);
    MDDIvarScan(value, path, depth + 1, visited);
}

static void MDDIvarScan(id obj, NSString *path, int depth, NSMutableSet<NSValue *> *visited) {
    if (!obj || depth > 3 || gDDeep.count >= 1000) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)obj];
    if ([visited containsObject:key]) return;
    [visited addObject:key];

    Class cls = object_getClass(obj);
    int hops = 0;
    while (cls && hops < 8) {
        NSString *className = NSStringFromClass(cls);
        if ([className isEqualToString:@"NSObject"] || [className isEqualToString:@"UIView"] ||
            [className isEqualToString:@"UIResponder"] || [className isEqualToString:@"UIViewController"]) {
            break;
        }
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            const char *name = ivar_getName(ivars[i]);
            id value = nil;
            @try {
                value = object_getIvar(obj, ivars[i]);
            } @catch (NSException *exception) {
                value = nil;
            }
            if (!value) continue;
            NSString *childPath = [NSString stringWithFormat:@"%@.%s", path, name ?: "?"];
            MDDScanValue(value, childPath, depth, visited);
        }
        free(ivars);
        cls = class_getSuperclass(cls);
        hops++;
    }
}

static void MDDDumpClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) {
        MDDDeepAdd([NSString stringWithFormat:@"NOCLASS %@", name]);
        return;
    }
    NSArray<NSString *> *keys = @[@"seen", @"mark", @"read", @"url", @"source", @"download", @"save",
                                  @"share", @"sponsor", @"advert", @"media", @"hide", @"remove",
                                  @"impression", @"playback", @"asset", @"video"];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    int shown = 0;
    for (unsigned int i = 0; i < methodCount && shown < 70; i++) {
        NSString *selector = NSStringFromSelector(method_getName(methods[i]));
        if (MDDContainsAny(selector.lowercaseString, keys)) {
            if (MDDDeepAdd([NSString stringWithFormat:@"M %@ -%@", name, selector])) shown++;
        }
    }
    free(methods);

    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    for (unsigned int i = 0; i < ivarCount && i < 60; i++) {
        const char *ivarName = ivar_getName(ivars[i]);
        const char *ivarType = ivar_getTypeEncoding(ivars[i]);
        MDDDeepAdd([NSString stringWithFormat:@"IVN %@ .%s %s", name, ivarName ?: "?", ivarType ?: "?"]);
    }
    free(ivars);
}

static void MDDDumpClassNames(void) {
    unsigned int total = 0;
    Class *list = objc_copyClassList(&total);
    if (!list) return;
    NSUInteger reel = 0, snacks = 0, sponsor = 0, player = 0;
    for (unsigned int i = 0; i < total; i++) {
        const char *name = class_getName(list[i]);
        if (!name) continue;
        if (reel < 120 && strcasestr(name, "reel")) {
            if (MDDDeepAdd([NSString stringWithFormat:@"CLASS %s", name])) reel++;
        } else if (snacks < 200 && strcasestr(name, "snacks")) {
            if (MDDDeepAdd([NSString stringWithFormat:@"CLASS %s", name])) snacks++;
        } else if (sponsor < 60 && (strcasestr(name, "sponsor") || strcasestr(name, "advert"))) {
            if (MDDDeepAdd([NSString stringWithFormat:@"CLASS %s", name])) sponsor++;
        } else if (player < 80 && strstr(name, "FBVideoPlayer")) {
            if (MDDDeepAdd([NSString stringWithFormat:@"CLASS %s", name])) player++;
        }
    }
    free(list);
}

static void MDDDeepVCs(UIViewController *vc, int depth) {
    if (!vc || depth > 10) return;
    NSString *name = NSStringFromClass([vc class]);
    if ([name containsString:@"SnacksMediaContainer"] ||
        [name isEqualToString:@"FBSnacksBucketViewController"] ||
        [name containsString:@"SnacksThreadContainer"]) {
        NSMutableSet<NSValue *> *visited = [NSMutableSet set];
        MDDIvarScan(vc, name, 0, visited);
    }
    for (UIViewController *child in vc.childViewControllers) MDDDeepVCs(child, depth + 1);
    if (vc.presentedViewController) MDDDeepVCs(vc.presentedViewController, depth + 1);
}

static void MDDDeepViews(UIView *v, int depth, int *count, int *found) {
    if (!v || depth > 45 || *count > 6000 || v.hidden) return;
    (*count)++;
    NSString *name = NSStringFromClass([v class]);
    if ([name isEqualToString:@"FBVideoPlayerComponentStatefulView"] && *found < 3) {
        CGRect f = [v convertRect:v.bounds toView:nil];
        if (CGRectIntersectsRect(f, UIScreen.mainScreen.bounds)) {
            (*found)++;
            NSMutableSet<NSValue *> *visited = [NSMutableSet set];
            MDDIvarScan(v, name, 0, visited);
        }
    }
    for (UIView *sub in v.subviews) MDDDeepViews(sub, depth + 1, count, found);
}

static void MDDDeep(void) {
    @try {
        MDDDumpClassNames();
        NSArray<NSString *> *names = @[@"FBVideoPlayerComponentStatefulView", @"FBVideoPlaybackContainerView",
                                       @"VideoContainerView", @"FBSnacksViewerViewController",
                                       @"FBSnacksBucketViewController", @"FBSnacksMediaContainerViewController",
                                       @"FBSnacksThreadContainerViewController",
                                       @"FBSnacksThreadSwitcherViewController",
                                       @"FBSnacksViewerBucketsCollectionViewController",
                                       @"FBSnacksAdsThreadViewController",
                                       @"FBVideoHomeUnifiedPlayerViewController",
                                       @"FBNewsFeedViewController"];
        for (NSString *name in names) MDDDumpClass(name);

        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window == gDWindow || window.hidden) continue;
                MDDDeepVCs(window.rootViewController, 0);
                int count = 0;
                int found = 0;
                MDDDeepViews(window, 0, &count, &found);
            }
        }
    } @catch (NSException *exception) {
        MDDDeepAdd([NSString stringWithFormat:@"EXC %@", exception.reason]);
    }
}

#pragma mark - Reports and sharing

static NSString *MDDHeader(NSString *title, NSUInteger lines) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"%@\nFacebook %@ (%@)\niOS %@ | lines=%lu\n\n",
            title, info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"],
            UIDevice.currentDevice.systemVersion, (unsigned long)lines];
}

static NSString *MDDReport(NSArray<NSString *> *lines, NSString *title) {
    NSMutableString *s = [NSMutableString stringWithString:MDDHeader(title, lines.count)];
    for (NSString *line in lines) [s appendFormat:@"%@\n", line];
    return s;
}

static UIViewController *MDDTopViewController(void) {
    UIWindow *key = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { key = window; break; }
        }
        if (key) break;
    }
    UIViewController *controller = key.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

static void MDDShareText(NSString *text, NSString *fileName) {
    UIViewController *presenter = MDDTopViewController();
    if (!presenter) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSError *error = nil;
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) return;
    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                          applicationActivities:nil];
    if (share.popoverPresentationController) {
        share.popoverPresentationController.sourceView = presenter.view;
        share.popoverPresentationController.sourceRect =
            CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    }
    [presenter presentViewController:share animated:YES completion:nil];
}

static void MDDClear(void) {
    [gDLines removeAllObjects];
    [gDSeen removeAllObjects];
    [gDDeep removeAllObjects];
    [gDDeepSeen removeAllObjects];
    gDCellLines = 0;
    gDMarkLines = 0;
    gDCtrlLines = 0;
    gDPlayerLines = 0;
}

#pragma mark - Buttons window

@interface MDDWindow : UIWindow
@end

@implementation MDDWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

@interface MDDRoot : UIViewController
@property (nonatomic, strong) UIButton *logButton;
@property (nonatomic, strong) UIButton *deepButton;
@end

@implementation MDDRoot

- (UIButton *)makeButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 46, 46);
    button.backgroundColor = color;
    button.layer.cornerRadius = 23;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.logButton = [self makeButton:@"LOG"
                                color:[UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.9]
                               action:@selector(logTapped)];
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)];
    [self.logButton addGestureRecognizer:press];
    [self.view addSubview:self.logButton];

    self.deepButton = [self makeButton:@"DEEP"
                                 color:[UIColor colorWithRed:0.10 green:0.35 blue:0.85 alpha:0.9]
                                action:@selector(deepTapped)];
    [self.view addSubview:self.deepButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat y = self.view.bounds.size.height * 0.35;
    self.logButton.center = CGPointMake(34, y);
    self.deepButton.center = CGPointMake(34, y + 56);
}

- (void)logTapped {
    MDDScan();
    MDDShareText(MDDReport(gDLines, @"MooDfacebook discovery v2 (LOG)"),
                 @"MooDfacebook-discovery.txt");
}

- (void)deepTapped {
    MDDScan();
    MDDDeep();
    MDDShareText(MDDReport(gDDeep, @"MooDfacebook discovery v2 (DEEP)"),
                 @"MooDfacebook-deep.txt");
}

- (void)pressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    MDDClear();
    UIColor *original = self.logButton.backgroundColor;
    self.logButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.2 alpha:0.9];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.logButton.backgroundColor = original;
    });
}

@end

static void MDDEnsureWindow(void) {
    if (gDWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return;
    MDDWindow *window = [[MDDWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert - 2;
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = [[MDDRoot alloc] init];
    window.hidden = NO;
    gDWindow = window;
}

__attribute__((constructor)) static void MDDInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *timer = [NSTimer timerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
            (void)t;
            MDDEnsureWindow();
            MDDScan();
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
