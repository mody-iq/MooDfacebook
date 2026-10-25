// Discovery.m — MooDfacebook temporary discovery logger.
// Records the real class names / texts / media sources of the Facebook UI.
// A small LOG button appears on the left: tap = share the log file,
// long press = clear the log.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static NSMutableArray<NSString *> *gDLines;
static NSMutableSet<NSString *> *gDSeen;
static NSUInteger gDCellLines = 0;
static NSUInteger gDMarkLines = 0;
static NSUInteger gDCtrlLines = 0;
static NSUInteger gDPlayerLines = 0;
static NSUInteger gDNodes = 0;
static UIWindow *gDWindow = nil;

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
    if ([gDSeen containsObject:line] || gDLines.count >= 700) return NO;
    [gDSeen addObject:line];
    [gDLines addObject:line];
    return YES;
}

static NSString *MDDURL(NSURL *u) {
    if (!u) return @"(nil)";
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    c.query = nil;
    c.fragment = nil;
    NSString *s = c.string ?: u.scheme;
    return MDDClip(s, 160);
}

static NSString *MDDChain(UIView *v, int hops) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *current = v;
    int n = 0;
    while (current && n < hops) {
        NSString *name = NSStringFromClass([current class]);
        NSString *ident = current.accessibilityIdentifier;
        if ([ident isKindOfClass:[NSString class]] && ident.length) {
            name = [NSString stringWithFormat:@"%@{%@}", name, MDDClip(ident, 30)];
        }
        [parts addObject:name];
        current = current.superview;
        n++;
    }
    return [parts componentsJoinedByString:@" < "];
}

static void MDDTexts(UIView *v, NSMutableArray<NSString *> *out, int depth, int maxDepth) {
    if (!v || depth > maxDepth || out.count >= 14) return;
    NSString *label = v.accessibilityLabel;
    if ([label isKindOfClass:[NSString class]] && label.length) {
        [out addObject:[@"a:" stringByAppendingString:MDDClip(label, 40)]];
    }
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text;
        if (t.length) [out addObject:[@"t:" stringByAppendingString:MDDClip(t, 40)]];
    }
    for (UIView *sub in v.subviews) MDDTexts(sub, out, depth + 1, maxDepth);
}

static BOOL MDDIsMarker(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length || text.length > 80) return NO;
    NSString *lower = text.lowercaseString;
    NSArray<NSString *> *keys = @[@"sponsored", @"suggested for you", @"people you may know",
                                  @"reels", @"short videos", @"ممول", @"مقترح",
                                  @"أشخاص قد تعرفهم"];
    for (NSString *key in keys) {
        if ([lower containsString:key]) return YES;
    }
    return NO;
}

static void MDDWalk(UIView *v, CGRect screen, int depth) {
    if (!v || depth > 45 || gDNodes > 6000 || v.hidden) return;
    gDNodes++;
    NSString *cls = NSStringFromClass([v class]);
    NSString *label = v.accessibilityLabel;

    // 1. Marker words (Sponsored / Suggested / PYMK / Reels): log the full chain.
    NSString *text = nil;
    if ([v isKindOfClass:[UILabel class]]) text = ((UILabel *)v).text;
    NSString *hit = MDDIsMarker(label) ? label : (MDDIsMarker(text) ? text : nil);
    if (hit && gDMarkLines < 100) {
        NSString *line = [NSString stringWithFormat:@"MARK \"%@\" in %@ | chain: %@",
                          MDDClip(hit, 40), cls, MDDChain(v, 12)];
        if (MDDAdd(line)) gDMarkLines++;
    }

    // 2. Visible feed cells.
    if ([v isKindOfClass:[UICollectionViewCell class]] || [v isKindOfClass:[UITableViewCell class]]) {
        CGRect f = [v convertRect:v.bounds toView:nil];
        if (CGRectIntersectsRect(f, screen) && gDCellLines < 80) {
            NSMutableArray<NSString *> *texts = [NSMutableArray array];
            MDDTexts(v, texts, 0, 4);
            NSString *line = [NSString stringWithFormat:@"CELL %@ h=%.0f chain: %@ | %@",
                              cls, f.size.height, MDDChain(v.superview, 4),
                              [texts componentsJoinedByString:@" ; "]];
            if (MDDAdd(line)) gDCellLines++;
        }
    }

    // 3. Video layers (AVPlayerLayer or the sample-buffer layer).
    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:v.layer];
    if (v.layer.sublayers) [layers addObjectsFromArray:v.layer.sublayers];
    for (CALayer *layer in layers) {
        if (gDPlayerLines >= 30) break;
        if ([layer isKindOfClass:[AVPlayerLayer class]]) {
            AVPlayer *player = ((AVPlayerLayer *)layer).player;
            AVAsset *asset = player.currentItem.asset;
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

    // 4. Like controls and the exact actions they fire.
    if ([v isKindOfClass:[UIControl class]] && gDCtrlLines < 40) {
        NSString *lowLabel = label.lowercaseString;
        NSString *lowClass = cls.lowercaseString;
        if ([lowLabel containsString:@"like"] || [lowLabel containsString:@"إعجاب"] ||
            [lowClass containsString:@"like"]) {
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
    if (!vc || depth > 8) return;
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

#pragma mark - Report

static NSString *MDDReport(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"MooDfacebook discovery\nFacebook %@ (%@)\niOS %@ | lines=%lu\n\n",
     info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"],
     UIDevice.currentDevice.systemVersion, (unsigned long)gDLines.count];
    for (NSString *line in gDLines) [s appendFormat:@"%@\n", line];
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

static void MDDShare(void) {
    MDDScan();
    UIViewController *presenter = MDDTopViewController();
    if (!presenter) return;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MooDfacebook-discovery.txt"];
    NSError *error = nil;
    [MDDReport() writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
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
    gDCellLines = 0;
    gDMarkLines = 0;
    gDCtrlLines = 0;
    gDPlayerLines = 0;
}

#pragma mark - LOG button window

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
@property (nonatomic, strong) UIButton *button;
@end

@implementation MDDRoot

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 46, 46);
    button.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.9];
    button.layer.cornerRadius = 23;
    [button setTitle:@"LOG" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [button addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)];
    [button addGestureRecognizer:press];
    [self.view addSubview:button];
    self.button = button;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.button.center = CGPointMake(34, self.view.bounds.size.height * 0.35);
}

- (void)tapped {
    MDDShare();
}

- (void)pressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    MDDClear();
    self.button.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.2 alpha:0.9];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.button.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.9];
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
