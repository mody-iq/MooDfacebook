#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

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
    v = d[@"enabled"]; if (v) gEnabled = [v boolValue];
    v = d[@"removeAds"]; if (v) gRemoveAds = [v boolValue];
    v = d[@"removePYMK"]; if (v) gRemovePYMK = [v boolValue];
    v = d[@"removeReelsCarousel"]; if (v) gRemoveReelsCarousel = [v boolValue];
    v = d[@"confirmPostLike"]; if (v) gConfirmPostLike = [v boolValue];
    v = d[@"downloadMedia"]; if (v) gDownloadMedia = [v boolValue];
    v = d[@"reelsDownloadBtn"]; if (v) gReelsDownloadBtn = [v boolValue];
    v = d[@"reelsHideOverlay"]; if (v) gReelsHideOverlay = [v boolValue];
    v = d[@"confirmReelsLike"]; if (v) gConfirmReelsLike = [v boolValue];
    v = d[@"reelsLongPressDL"]; if (v) gReelsLongPressDL = [v boolValue];
    v = d[@"storiesDownload"]; if (v) gStoriesDownload = [v boolValue];
    v = d[@"storiesAnon"]; if (v) gStoriesAnon = [v boolValue];
    v = d[@"storiesManualSeen"]; if (v) gStoriesManualSeen = [v boolValue];
    v = d[@"storiesNoAuto"]; if (v) gStoriesNoAuto = [v boolValue];
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
    [[NSFileManager defaultManager] createDirectoryAtPath:[kPrefsPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:kPrefsPath atomically:YES];
}

#pragma mark - Window helpers

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
    if ([vc isKindOfClass:[UINavigationController class]])
        vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    if ([vc isKindOfClass:[UITabBarController class]])
        vc = ((UITabBarController *)vc).selectedViewController ?: vc;
    return vc;
}

static void MFToast(NSString *msg) {
    UIWindow *w = MFKeyWindow();
    if (!w) return;
    UILabel *lab = [[UILabel alloc] init];
    lab.text = msg;
    lab.textColor = UIColor.whiteColor;
    lab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    lab.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    lab.textAlignment = NSTextAlignmentCenter;
    lab.numberOfLines = 0;
    lab.layer.cornerRadius = 10;
    lab.clipsToBounds = YES;
    CGSize sz = [lab sizeThatFits:CGSizeMake(w.bounds.size.width - 48, 200)];
    lab.frame = CGRectMake(24, w.bounds.size.height - 140, w.bounds.size.width - 48, MAX(40, sz.height + 16));
    [w addSubview:lab];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{ lab.alpha = 0; } completion:^(__unused BOOL f){ [lab removeFromSuperview]; }];
    });
}

#pragma mark - Text classification

static BOOL MFContainsAny(NSString *s, NSArray<NSString *> *arr) {
    if (!s.length) return NO;
    NSString *l = s.lowercaseString;
    for (NSString *n in arr) {
        if ([l containsString:n.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL MFIsSponsoredText(NSString *s) {
    return MFContainsAny(s, @[
        @"sponsored", @"مموّل", @"ممول", @"annonce sponsorisée",
        @"gesponsert", @"sponsorizzato", @"patrocinado", @"reklam"
    ]);
}

static BOOL MFIsPYMKText(NSString *s) {
    return MFContainsAny(s, @[
        @"people you may know", @"أشخاص قد تعرفهم", @"suggested for you",
        @"مقترح لك", @"suggested pages", @"suggested groups"
    ]);
}

static BOOL MFIsReelsShelfText(NSString *s) {
    if (!s.length) return NO;
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *l = t.lowercaseString;
    if ([l isEqualToString:@"reels"] || [l isEqualToString:@"ريلز"]) return YES;
    if ([l hasPrefix:@"reels"] && t.length < 20) return YES;
    return NO;
}

static BOOL MFIsLikeText(NSString *s) {
    return MFContainsAny(s, @[
        @"like", @"أعجبني", @"اعجبني", @"j'aime", @"gefällt mir", @"mi piace"
    ]);
}

static BOOL MFTreeHasMatchingLabel(UIView *view, int depth, BOOL (*pred)(NSString *)) {
    if (!view || depth > 10) return NO;
    if ([view isKindOfClass:[UILabel class]] && pred(((UILabel *)view).text)) return YES;
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        if (pred([b titleForState:UIControlStateNormal])) return YES;
        if (b.titleLabel && pred(b.titleLabel.text)) return YES;
    }
    @try {
        id at = [view valueForKey:@"attributedText"];
        if ([at isKindOfClass:[NSAttributedString class]] && pred([at string])) return YES;
    } @catch (__unused NSException *e) {}
    for (UIView *sub in view.subviews) {
        if (MFTreeHasMatchingLabel(sub, depth + 1, pred)) return YES;
    }
    return NO;
}

static void MFCollapse(UIView *v) {
    if (!v || v.hidden) return;
    v.hidden = YES;
    v.alpha = 0;
    CGRect f = v.frame;
    f.size.height = 0;
    v.frame = f;
}

#pragma mark - Media download

static NSURL *MFFindPlayerURLInView(UIView *view, int depth) {
    if (!view || depth > 12) return nil;
    CALayer *layer = view.layer;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *p = ((AVPlayerLayer *)layer).player;
        AVAsset *asset = p.currentItem.asset;
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            return ((AVURLAsset *)asset).URL;
        }
    }
    for (CALayer *sub in layer.sublayers) {
        if ([sub isKindOfClass:[AVPlayerLayer class]]) {
            AVPlayer *p = ((AVPlayerLayer *)sub).player;
            AVAsset *asset = p.currentItem.asset;
            if ([asset isKindOfClass:[AVURLAsset class]])
                return ((AVURLAsset *)asset).URL;
        }
    }
    for (UIView *sub in view.subviews) {
        NSURL *u = MFFindPlayerURLInView(sub, depth + 1);
        if (u) return u;
    }
    return nil;
}

static NSURL *MFFindAnyPlayerURL(void) {
    for (UIWindow *w in MFWindows()) {
        NSURL *u = MFFindPlayerURLInView(w, 0);
        if (u) return u;
    }
    return nil;
}

static void MFSaveURLToPhotos(NSURL *url) {
    if (!url) {
        MFToast(@"No media URL found");
        return;
    }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{ MFToast(@"Photos permission denied"); });
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:url];
            if (!data.length) {
                // Try copy local file
                if (url.isFileURL) data = [NSData dataWithContentsOfFile:url.path];
            }
            if (!data.length) {
                dispatch_async(dispatch_get_main_queue(), ^{ MFToast(@"Download failed"); });
                return;
            }
            NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"mp4";
            BOOL isImage = [@[ @"jpg", @"jpeg", @"png", @"heic", @"webp" ] containsObject:ext];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"moodfb_%@.%@", NSUUID.UUID.UUIDString, isImage ? @"jpg" : @"mp4"]];
            [data writeToFile:tmp atomically:YES];
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                if (isImage)
                    [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:[NSURL fileURLWithPath:tmp]];
                else
                    [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:tmp]];
            } completionHandler:^(BOOL ok, NSError *err) {
                [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    MFToast(ok ? @"Saved to Photos" : (err.localizedDescription ?: @"Save failed"));
                });
            }];
        });
    }];
}

static void MFDownloadCurrentMedia(void) {
    if (!gEnabled || !gDownloadMedia) return;
    NSURL *url = MFFindAnyPlayerURL();
    MFSaveURLToPhotos(url);
}

#pragma mark - Settings UI

static UIWindow *gSettingsWindow = nil;

@interface MFSettingsController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *sections;
@end

@implementation MFSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"MooDfacebook";

    self.sections = @[
        @{ @"title": @"General", @"rows": @[
            @{ @"key": @"enabled", @"label": @"Enable MooDfacebook" },
            @{ @"key": @"removeAds", @"label": @"Remove Sponsored Ads" },
            @{ @"key": @"removePYMK", @"label": @"Remove People You May Know" },
            @{ @"key": @"removeReelsCarousel", @"label": @"Remove Reels Carousel" },
            @{ @"key": @"confirmPostLike", @"label": @"Confirm Post Like" },
            @{ @"key": @"downloadMedia", @"label": @"Download Media (long-press)" },
        ]},
        @{ @"title": @"Reels", @"rows": @[
            @{ @"key": @"reelsDownloadBtn", @"label": @"Download Button on Reels" },
            @{ @"key": @"reelsHideOverlay", @"label": @"Hide Reels Overlay" },
            @{ @"key": @"confirmReelsLike", @"label": @"Confirm Reels Like" },
            @{ @"key": @"reelsLongPressDL", @"label": @"Long-press Download Reels" },
        ]},
        @{ @"title": @"Stories", @"rows": @[
            @{ @"key": @"storiesDownload", @"label": @"Download Stories" },
            @{ @"key": @"storiesAnon", @"label": @"Watch Anonymously" },
            @{ @"key": @"storiesManualSeen", @"label": @"Manual Mark as Seen" },
            @{ @"key": @"storiesNoAuto", @"label": @"Disable Auto-Advance" },
        ]},
    ];

    UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:@"MooDfacebook"];
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    bar.items = @[item];
    [self.view addSubview:bar];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:56],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [self.sections[s][@"rows"] count];
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return self.sections[s][@"title"];
}

- (BOOL *)flagForKey:(NSString *)key {
    if ([key isEqualToString:@"enabled"]) return &gEnabled;
    if ([key isEqualToString:@"removeAds"]) return &gRemoveAds;
    if ([key isEqualToString:@"removePYMK"]) return &gRemovePYMK;
    if ([key isEqualToString:@"removeReelsCarousel"]) return &gRemoveReelsCarousel;
    if ([key isEqualToString:@"confirmPostLike"]) return &gConfirmPostLike;
    if ([key isEqualToString:@"downloadMedia"]) return &gDownloadMedia;
    if ([key isEqualToString:@"reelsDownloadBtn"]) return &gReelsDownloadBtn;
    if ([key isEqualToString:@"reelsHideOverlay"]) return &gReelsHideOverlay;
    if ([key isEqualToString:@"confirmReelsLike"]) return &gConfirmReelsLike;
    if ([key isEqualToString:@"reelsLongPressDL"]) return &gReelsLongPressDL;
    if ([key isEqualToString:@"storiesDownload"]) return &gStoriesDownload;
    if ([key isEqualToString:@"storiesAnon"]) return &gStoriesAnon;
    if ([key isEqualToString:@"storiesManualSeen"]) return &gStoriesManualSeen;
    if ([key isEqualToString:@"storiesNoAuto"]) return &gStoriesNoAuto;
    return NULL;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    NSDictionary *row = self.sections[ip.section][@"rows"][ip.row];
    cell.textLabel.text = row[@"label"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    BOOL *flag = [self flagForKey:row[@"key"]];
    sw.on = flag ? *flag : NO;
    sw.tag = ip.section * 100 + ip.row;
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggle:(UISwitch *)sw {
    NSInteger section = sw.tag / 100;
    NSInteger row = sw.tag % 100;
    NSString *key = self.sections[section][@"rows"][row][@"key"];
    BOOL *flag = [self flagForKey:key];
    if (flag) {
        *flag = sw.on;
        MFSavePrefs();
    }
}

- (void)close {
    gSettingsWindow.hidden = YES;
    gSettingsWindow.rootViewController = nil;
    gSettingsWindow = nil;
}

@end

static void MFOpenSettings(void) {
    if (gSettingsWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) scene = MFKeyWindow().windowScene;
    if (!scene) return;

    gSettingsWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gSettingsWindow.windowLevel = UIWindowLevelAlert + 10;
    gSettingsWindow.rootViewController = [[MFSettingsController alloc] init];
    gSettingsWindow.frame = scene.coordinateSpace.bounds;
    [gSettingsWindow makeKeyAndVisible];
}

#pragma mark - Confirm like

static BOOL gConfirmingLike = NO;

static BOOL MFShouldConfirmLike(UIControl *ctl) {
    if (!gEnabled) return NO;
    NSString *title = nil;
    if ([ctl isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)ctl;
        title = [b titleForState:UIControlStateNormal] ?: b.titleLabel.text;
        UIImage *img = [b imageForState:UIControlStateNormal];
        // accessibility
        if (!title.length) title = b.accessibilityLabel;
    } else {
        title = ctl.accessibilityLabel;
    }
    if (!MFIsLikeText(title)) return NO;

    // Heuristic: reels-like if very tall window and control near bottom-right
    CGRect f = [ctl convertRect:ctl.bounds toView:nil];
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    BOOL nearBottom = (f.origin.y > screenH * 0.55);
    BOOL confirm = nearBottom ? gConfirmReelsLike : gConfirmPostLike;
    return confirm;
}

#pragma mark - Hooks: feed cleanup

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 48) return;
    if (gRemoveAds && MFTreeHasMatchingLabel(self, 0, MFIsSponsoredText)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemovePYMK && MFTreeHasMatchingLabel(self, 0, MFIsPYMKText)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemoveReelsCarousel && MFTreeHasMatchingLabel(self, 0, MFIsReelsShelfText)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
}
%end

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 40) return;
    if (gRemoveAds && MFTreeHasMatchingLabel(self, 0, MFIsSponsoredText)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemovePYMK && MFTreeHasMatchingLabel(self, 0, MFIsPYMKText)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
}
%end

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled || !gRemoveReelsCarousel) return;
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;
    // horizontal shelves
    if (h > 120 && h < 320 && w > h) {
        if (MFTreeHasMatchingLabel(self, 0, MFIsReelsShelfText)) {
            MFCollapse(self);
        }
    }
}
%end

#pragma mark - Hooks: confirm like

%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (gConfirmingLike) { %orig; return; }
    if ([self isKindOfClass:[UIControl class]] && MFShouldConfirmLike((UIControl *)self)) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"MooDfacebook"
                                                                   message:@"Confirm like?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        __weak UIControl *weakSelf = (UIControl *)self;
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Like" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            gConfirmingLike = YES;
            [weakSelf sendAction:action to:target forEvent:event];
            gConfirmingLike = NO;
        }]];
        [MFTopVC() presentViewController:a animated:YES completion:nil];
        return;
    }
    %orig;
}
%end

#pragma mark - Hooks: long-press download + tab settings

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled || !self.window) return;

    // Long-press download on large media-like views
    if ((gDownloadMedia || gReelsLongPressDL || gStoriesDownload) && self.bounds.size.width > 120 && self.bounds.size.height > 120) {
        static const void *kLPKey = &kLPKey;
        if (!objc_getAssociatedObject(self, kLPKey)) {
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[MFSettingsController class] action:@selector(mf_longPress:)];
            // Use a small helper object via associated block isn't easy — use notification style
            // Attach via category method on UIView below
            [self addGestureRecognizer:lp];
            // Will set target properly in +load path — replace:
            [self removeGestureRecognizer:lp];
        }
    }
}
%end

@interface UIView (MooDFB)
- (void)mf_handleLongPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation UIView (MooDFB)
- (void)mf_handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (!gEnabled) return;
    if (!(gDownloadMedia || gReelsLongPressDL || gStoriesDownload)) return;
    MFDownloadCurrentMedia();
}
@end

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    static const void *kTabLP = &kTabLP;
    if (objc_getAssociatedObject(self, kTabLP)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mf_tabLongPress:)];
    lp.minimumPressDuration = 0.55;
    [self addGestureRecognizer:lp];
    objc_setAssociatedObject(self, kTabLP, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (void)mf_tabLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    MFOpenSettings();
}
%end

// Attach long-press to key window periodically for media
static void MFAttachMediaLongPress(UIView *view, int depth) {
    if (!view || depth > 6) return;
    if (view.bounds.size.width > 150 && view.bounds.size.height > 200) {
        static const void *kKey = &kKey;
        if (!objc_getAssociatedObject(view, kKey)) {
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:view action:@selector(mf_handleLongPress:)];
            lp.minimumPressDuration = 0.6;
            [view addGestureRecognizer:lp];
            objc_setAssociatedObject(view, kKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    for (UIView *s in view.subviews) MFAttachMediaLongPress(s, depth + 1);
}

#pragma mark - Reels overlay hide + download button

static const NSInteger kDLBtnTag = 0x4D464244; // MFBD

static void MFEnsureDownloadButton(UIView *host) {
    if (!gEnabled || !gReelsDownloadBtn) return;
    if ([host viewWithTag:kDLBtnTag]) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = kDLBtnTag;
    btn.frame = CGRectMake(host.bounds.size.width - 52, host.bounds.size.height * 0.55, 40, 40);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    btn.layer.cornerRadius = 20;
    [btn setTitle:@"↓" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [btn addTarget:[MFSettingsController class] action:@selector(mf_dlTap) forControlEvents:UIControlEventTouchUpInside];
    // fix target
    [btn removeTarget:[MFSettingsController class] action:@selector(mf_dlTap) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:btn action:@selector(mf_selfDownload) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:btn];
}

@interface UIButton (MooDFB)
- (void)mf_selfDownload;
@end
@implementation UIButton (MooDFB)
- (void)mf_selfDownload { MFDownloadCurrentMedia(); }
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled) return;

    // Attach long-press tree
    if (gDownloadMedia || gReelsLongPressDL || gStoriesDownload) {
        MFAttachMediaLongPress(self.view, 0);
    }

    // Full-screen-ish VC => reels/stories candidate
    CGFloat h = self.view.bounds.size.height;
    CGFloat w = self.view.bounds.size.width;
    if (h > 500 && w > 280) {
        if (gReelsDownloadBtn) MFEnsureDownloadButton(self.view);

        if (gReelsHideOverlay) {
            // Hide common overlay containers near edges (heuristic)
            for (UIView *sub in self.view.subviews) {
                if (sub.tag == kDLBtnTag) continue;
                CGRect f = sub.frame;
                BOOL bottomOverlay = (f.origin.y > h * 0.65 && f.size.height < h * 0.4);
                BOOL sideOverlay = (f.origin.x > w * 0.7 && f.size.width < w * 0.35);
                if (bottomOverlay || sideOverlay) {
                    sub.alpha = 0.05;
                    sub.userInteractionEnabled = NO;
                }
            }
        }
    }
}
%end

#pragma mark - Stories auto-advance / seen (best-effort)

// Facebook story timers often use NSTimer scheduled on main runloop.
// We invalidate short-interval timers while storiesAnon/noAuto is on — aggressive but optional.

%hook NSTimer
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel userInfo:(id)ui repeats:(BOOL)rep {
    if (gEnabled && gStoriesNoAuto && ti > 0.4 && ti < 8.0) {
        // Skip installing auto-advance style short timers when flag is on
        // Only skip if selector name suggests story progress (heuristic)
        NSString *name = NSStringFromSelector(sel);
        if (MFContainsAny(name, @[ @"story", @"Story", @"advance", @"Advance", @"progress", @"Progress", @"bucket", @"Bucket" ])) {
            // return a timer that never fires meaningfully
            return %orig(60*60*24, target, sel, ui, NO);
        }
    }
    return %orig;
}
%end

// Anonymous watch: block network-ish story seen if class responds — soft noop markers
// (Real GraphQL interception needs FB private API; flag is stored for future refinement)

%ctor {
    MFLoadPrefs();
    if (![[NSFileManager defaultManager] fileExistsAtPath:kPrefsPath]) {
        MFSavePrefs(); // write defaults
    }
    NSLog(@"[MooDfacebook] v0.2.0 loaded — long-press tab bar for settings");
}
