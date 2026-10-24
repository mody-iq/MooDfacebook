#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist";
static const NSInteger kDLBtnTag = 777001;

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
static BOOL gConfirmingLike = NO;

// --- URL capture via AVPlayer hook ---
static NSMutableArray<NSURL *> *gCapturedURLs = nil;
static NSURL *gLastCapturedURL = nil;

static UIWindow *gSettingsWindow = nil;

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

static NSArray *MFWindows(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]])
            [a addObjectsFromArray:((UIWindowScene *)s).windows];
    }
    return a;
}

static UIWindow *MFKeyWindow(void) {
    for (UIWindow *w in MFWindows()) if (w.isKeyWindow) return w;
    return [MFWindows() firstObject];
}

static UIViewController *MFTopVC(void) {
    UIViewController *vc = MFKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void MFToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = MFKeyWindow();
        if (!w) return;
        UILabel *lab = [[UILabel alloc] init];
        lab.text = msg;
        lab.textColor = UIColor.whiteColor;
        lab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        lab.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.numberOfLines = 0;
        lab.layer.cornerRadius = 10;
        lab.clipsToBounds = YES;
        CGFloat width = w.bounds.size.width - 48;
        CGSize sz = [lab sizeThatFits:CGSizeMake(width, 120)];
        lab.frame = CGRectMake(24, w.bounds.size.height - 150, width, MAX(36, sz.height + 14));
        [w addSubview:lab];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{ lab.alpha = 0; }
                            completion:^(BOOL f){ [lab removeFromSuperview]; }];
        });
    });
}

static BOOL MFContains(NSString *s, NSArray *needles) {
    if (s.length == 0) return NO;
    NSString *l = s.lowercaseString;
    for (NSString *n in needles) {
        if ([l containsString:[n lowercaseString]]) return YES;
    }
    return NO;
}

static BOOL MFIsSponsored(NSString *s) {
    return MFContains(s, @[ @"sponsored", @"مموّل", @"ممول", @"gesponsert", @"sponsorizzato", @"patrocinado" ]);
}

static BOOL MFIsPYMK(NSString *s) {
    return MFContains(s, @[ @"people you may know", @"أشخاص قد تعرفهم", @"suggested for you", @"مقترح لك", @"suggested groups" ]);
}

static BOOL MFIsReelsLabel(NSString *s) {
    if (s.length == 0) return NO;
    NSString *t = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [t isEqualToString:@"reels"] || [t isEqualToString:@"ريلز"] || [t hasPrefix:@"reels "];
}

static BOOL MFIsLikeLabel(NSString *s) {
    return MFContains(s, @[ @"like", @"أعجبني", @"اعجبني", @"j'aime", @"gefällt mir" ]);
}

static BOOL MFScanLabels(UIView *view, int depth, BOOL (*check)(NSString *)) {
    if (!view || depth > 9) return NO;
    if ([view isKindOfClass:[UILabel class]] && check(((UILabel *)view).text)) return YES;
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        if (check([b titleForState:UIControlStateNormal])) return YES;
        if (check(b.accessibilityLabel)) return YES;
    }
    if (check(view.accessibilityLabel)) return YES;
    for (UIView *sub in view.subviews) {
        if (MFScanLabels(sub, depth + 1, check)) return YES;
    }
    return NO;
}

static void MFCollapse(UIView *v) {
    if (!v) return;
    v.hidden = YES;
    v.alpha = 0;
    CGRect f = v.frame;
    f.size.height = 0;
    v.frame = f;
}

// --- New URL capture: uses hooked AVPlayer ---
static void MFCaptureURL(NSURL *url) {
    if (!url) return;
    NSString *scheme = url.scheme.lowercaseString;
    // فقط HTTP/HTTPS URLs (مش file:// أو data://)
    if (![scheme hasPrefix:@"http"]) return;
    NSString *absStr = url.absoluteString;
    // فيسبوك CDN patterns
    if (![absStr containsString:@"facebook"] &&
        ![absStr containsString:@"fbcdn"] &&
        ![absStr containsString:@"cdninstagram"] &&
        ![absStr containsString:@"video"] &&
        ![absStr containsString:@".mp4"] &&
        ![absStr containsString:@".m3u8"]) return;

    @synchronized(gCapturedURLs) {
        if (![gCapturedURLs containsObject:url]) {
            [gCapturedURLs insertObject:url atIndex:0];
            if (gCapturedURLs.count > 20) [gCapturedURLs removeLastObject];
        }
        gLastCapturedURL = url;
    }
    NSLog(@"[MooDfacebook] Captured URL: %@", absStr);
}

static NSURL *MFGetBestURL(void) {
    @synchronized(gCapturedURLs) {
        return gLastCapturedURL ?: gCapturedURLs.firstObject;
    }
}

static void MFSaveURL(NSURL *url) {
    if (!url) {
        MFToast(@"❌ No media URL — play the video first");
        return;
    }
    MFToast(@"⬇️ Downloading...");
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{ MFToast(@"❌ Photos access denied"); });
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];
            [req setValue:@"https://www.facebook.com/" forHTTPHeaderField:@"Referer"];

            __block NSData *data = nil;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    data = d;
                    dispatch_semaphore_signal(sem);
                }];
            [task resume];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));

            if (!data.length) {
                dispatch_async(dispatch_get_main_queue(), ^{ MFToast(@"❌ Download failed"); });
                return;
            }
            NSString *ext = url.pathExtension.lowercaseString;
            if (!ext.length) ext = @"mp4";
            BOOL isImg = [@[@"jpg",@"jpeg",@"png",@"heic",@"webp"] containsObject:ext];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"mf_%@.%@", NSUUID.UUID.UUIDString, isImg ? @"jpg" : @"mp4"]];
            [data writeToFile:tmp atomically:YES];
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                NSURL *fu = [NSURL fileURLWithPath:tmp];
                if (isImg) [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:fu];
                else       [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fu];
            } completionHandler:^(BOOL ok, NSError *err) {
                [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    MFToast(ok ? @"✅ Saved to Photos!" : @"❌ Save failed");
                });
            }];
        });
    }];
}

static void MFDownload(void) {
    if (!gEnabled) return;
    MFSaveURL(MFGetBestURL());
}

#pragma mark - Settings

@interface MFSettingsController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *sections;
@end

@implementation MFSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.sections = @[
        @{ @"t": @"General", @"r": @[
            @{ @"k": @"enabled",             @"l": @"Enable MooDfacebook" },
            @{ @"k": @"removeAds",           @"l": @"Remove Sponsored Ads" },
            @{ @"k": @"removePYMK",          @"l": @"Remove People You May Know" },
            @{ @"k": @"removeReelsCarousel", @"l": @"Remove Reels Carousel" },
            @{ @"k": @"confirmPostLike",     @"l": @"Confirm Post Like" },
            @{ @"k": @"downloadMedia",       @"l": @"Download Media (long-press)" },
        ]},
        @{ @"t": @"Reels", @"r": @[
            @{ @"k": @"reelsDownloadBtn",  @"l": @"Download Button on Reels" },
            @{ @"k": @"reelsHideOverlay",  @"l": @"Hide Reels Overlay" },
            @{ @"k": @"confirmReelsLike",  @"l": @"Confirm Reels Like" },
            @{ @"k": @"reelsLongPressDL",  @"l": @"Long-press Download Reels" },
        ]},
        @{ @"t": @"Stories", @"r": @[
            @{ @"k": @"storiesDownload",    @"l": @"Download Stories" },
            @{ @"k": @"storiesAnon",        @"l": @"Watch Anonymously" },
            @{ @"k": @"storiesManualSeen",  @"l": @"Manual Mark as Seen" },
            @{ @"k": @"storiesNoAuto",      @"l": @"Disable Auto-Advance" },
        ]},
    ];

    UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:@"MooDfacebook ⚙️"];
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                            target:self action:@selector(close)];
    bar.items = @[item];
    [self.view addSubview:bar];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate   = self;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:56],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self.sections[s][@"r"] count]; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return self.sections[s][@"t"]; }

- (BOOL)valueForKeyName:(NSString *)key {
    if ([key isEqualToString:@"enabled"])             return gEnabled;
    if ([key isEqualToString:@"removeAds"])           return gRemoveAds;
    if ([key isEqualToString:@"removePYMK"])          return gRemovePYMK;
    if ([key isEqualToString:@"removeReelsCarousel"]) return gRemoveReelsCarousel;
    if ([key isEqualToString:@"confirmPostLike"])     return gConfirmPostLike;
    if ([key isEqualToString:@"downloadMedia"])       return gDownloadMedia;
    if ([key isEqualToString:@"reelsDownloadBtn"])    return gReelsDownloadBtn;
    if ([key isEqualToString:@"reelsHideOverlay"])    return gReelsHideOverlay;
    if ([key isEqualToString:@"confirmReelsLike"])    return gConfirmReelsLike;
    if ([key isEqualToString:@"reelsLongPressDL"])    return gReelsLongPressDL;
    if ([key isEqualToString:@"storiesDownload"])     return gStoriesDownload;
    if ([key isEqualToString:@"storiesAnon"])         return gStoriesAnon;
    if ([key isEqualToString:@"storiesManualSeen"])   return gStoriesManualSeen;
    if ([key isEqualToString:@"storiesNoAuto"])       return gStoriesNoAuto;
    return NO;
}

- (void)setValue:(BOOL)on forKeyName:(NSString *)key {
    if ([key isEqualToString:@"enabled"])             gEnabled = on;
    else if ([key isEqualToString:@"removeAds"])           gRemoveAds = on;
    else if ([key isEqualToString:@"removePYMK"])          gRemovePYMK = on;
    else if ([key isEqualToString:@"removeReelsCarousel"]) gRemoveReelsCarousel = on;
    else if ([key isEqualToString:@"confirmPostLike"])     gConfirmPostLike = on;
    else if ([key isEqualToString:@"downloadMedia"])       gDownloadMedia = on;
    else if ([key isEqualToString:@"reelsDownloadBtn"])    gReelsDownloadBtn = on;
    else if ([key isEqualToString:@"reelsHideOverlay"])    gReelsHideOverlay = on;
    else if ([key isEqualToString:@"confirmReelsLike"])    gConfirmReelsLike = on;
    else if ([key isEqualToString:@"reelsLongPressDL"])    gReelsLongPressDL = on;
    else if ([key isEqualToString:@"storiesDownload"])     gStoriesDownload = on;
    else if ([key isEqualToString:@"storiesAnon"])         gStoriesAnon = on;
    else if ([key isEqualToString:@"storiesManualSeen"])   gStoriesManualSeen = on;
    else if ([key isEqualToString:@"storiesNoAuto"])       gStoriesNoAuto = on;
    MFSavePrefs();
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    NSDictionary *row = self.sections[ip.section][@"r"][ip.row];
    cell.textLabel.text = row[@"l"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on  = [self valueForKeyName:row[@"k"]];
    sw.tag = ip.section * 100 + ip.row;
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)toggle:(UISwitch *)sw {
    NSInteger section = sw.tag / 100;
    NSInteger row     = sw.tag % 100;
    NSString *key = self.sections[section][@"r"][row][@"k"];
    [self setValue:sw.on forKeyName:key];
}

- (void)close {
    gSettingsWindow.hidden = YES;
    gSettingsWindow.rootViewController = nil;
    gSettingsWindow = nil;
}

@end

static void MFOpenSettings(void) {
    if (gSettingsWindow) return;
    UIWindowScene *scene = MFKeyWindow().windowScene;
    if (!scene) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
    }
    if (!scene) return;
    gSettingsWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gSettingsWindow.windowLevel = UIWindowLevelAlert + 20;
    gSettingsWindow.rootViewController = [[MFSettingsController alloc] init];
    gSettingsWindow.frame = scene.coordinateSpace.bounds;
    [gSettingsWindow makeKeyAndVisible];
}

@interface MFActionTarget : NSObject
+ (instancetype)shared;
- (void)download;
- (void)tabLongPress:(UILongPressGestureRecognizer *)gr;
- (void)mediaLongPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation MFActionTarget
+ (instancetype)shared {
    static MFActionTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MFActionTarget new]; });
    return s;
}
- (void)download { MFDownload(); }
- (void)tabLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) MFOpenSettings();
}
- (void)mediaLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) MFDownload();
}
@end

static void MFEnsureDLButton(UIView *host) {
    if (!gEnabled || !gReelsDownloadBtn) return;
    if ([host viewWithTag:kDLBtnTag]) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = kDLBtnTag;
    btn.frame = CGRectMake(host.bounds.size.width - 56, host.bounds.size.height * 0.45, 46, 46);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    btn.layer.cornerRadius = 23;
    [btn setTitle:@"⬇" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [btn addTarget:[MFActionTarget shared] action:@selector(download) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:btn];
}

static void MFAttachLongPress(UIView *view) {
    if (!view) return;
    static const void *kKey = &kKey;
    if (objc_getAssociatedObject(view, kKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[MFActionTarget shared] action:@selector(mediaLongPress:)];
    lp.minimumPressDuration = 0.55;
    [view addGestureRecognizer:lp];
    objc_setAssociatedObject(view, kKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Hooks

// Hook AVPlayer لالتقاط URL لحظة تحميل الفيديو
%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (!gEnabled) return;
    if (!item) return;
    AVAsset *asset = item.asset;
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        MFCaptureURL(((AVURLAsset *)asset).URL);
    }
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    self = %orig;
    if (self && item) {
        AVAsset *asset = item.asset;
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            MFCaptureURL(((AVURLAsset *)asset).URL);
        }
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    if (self && URL) {
        MFCaptureURL(URL);
    }
    return self;
}
%end

// Hook AVPlayerItem أيضاً للإحاطة الكاملة
%hook AVPlayerItem
- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    if (self && URL) MFCaptureURL(URL);
    return self;
}
- (instancetype)initWithAsset:(AVAsset *)asset {
    self = %orig;
    if (self && [asset isKindOfClass:[AVURLAsset class]]) {
        MFCaptureURL(((AVURLAsset *)asset).URL);
    }
    return self;
}
%end

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 48) return;
    if (gRemoveAds    && MFScanLabels(self, 0, MFIsSponsored))    { MFCollapse(self); self.contentView.hidden = YES; return; }
    if (gRemovePYMK   && MFScanLabels(self, 0, MFIsPYMK))         { MFCollapse(self); self.contentView.hidden = YES; return; }
    if (gRemoveReelsCarousel && MFScanLabels(self, 0, MFIsReelsLabel)) { MFCollapse(self); self.contentView.hidden = YES; return; }
}
%end

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 40) return;
    if (gRemoveAds  && MFScanLabels(self, 0, MFIsSponsored)) { MFCollapse(self); self.contentView.hidden = YES; return; }
    if (gRemovePYMK && MFScanLabels(self, 0, MFIsPYMK))      { MFCollapse(self); self.contentView.hidden = YES; return; }
}
%end

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled || !gRemoveReelsCarousel) return;
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;
    if (h > 120 && h < 340 && w > h && MFScanLabels(self, 0, MFIsReelsLabel)) {
        MFCollapse(self);
    }
}
%end

%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (gConfirmingLike) { %orig; return; }
    if (gEnabled && [self isKindOfClass:[UIControl class]]) {
        NSString *label = self.accessibilityLabel;
        if ([self isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)self;
            if (!label.length) label = [b titleForState:UIControlStateNormal];
            if (!label.length) label = b.titleLabel.text;
        }
        if (MFIsLikeLabel(label)) {
            CGRect f = [self convertRect:self.bounds toView:nil];
            BOOL nearBottom = (f.origin.y > UIScreen.mainScreen.bounds.size.height * 0.55);
            BOOL needConfirm = nearBottom ? gConfirmReelsLike : gConfirmPostLike;
            if (needConfirm) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MooDfacebook"
                    message:@"Confirm like?" preferredStyle:UIAlertControllerStyleAlert];
                __weak UIControl *weakSelf = self;
                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Like ❤️" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                    gConfirmingLike = YES;
                    [weakSelf sendAction:action to:target forEvent:event];
                    gConfirmingLike = NO;
                }]];
                [MFTopVC() presentViewController:alert animated:YES completion:nil];
                return;
            }
        }
    }
    %orig;
}
%end

%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    static const void *kTab = &kTab;
    if (objc_getAssociatedObject(self, kTab)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[MFActionTarget shared] action:@selector(tabLongPress:)];
    lp.minimumPressDuration = 0.5;
    [self addGestureRecognizer:lp];
    objc_setAssociatedObject(self, kTab, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled) return;
    CGFloat h = self.view.bounds.size.height;
    CGFloat w = self.view.bounds.size.width;
    if (h > 500 && w > 280) {
        if (gReelsDownloadBtn) MFEnsureDLButton(self.view);
        if (gDownloadMedia || gReelsLongPressDL || gStoriesDownload) MFAttachLongPress(self.view);
        if (gReelsHideOverlay) {
            for (UIView *sub in self.view.subviews) {
                if (sub.tag == kDLBtnTag) continue;
                CGRect f = sub.frame;
                if ((f.origin.y > h * 0.65 && f.size.height < h * 0.4) ||
                    (f.origin.x > w  * 0.7  && f.size.width  < w * 0.35)) {
                    sub.alpha = 0.08;
                    sub.userInteractionEnabled = NO;
                }
            }
        }
    }
}
%end

%hook NSTimer
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel userInfo:(id)ui repeats:(BOOL)rep {
    if (gEnabled && gStoriesNoAuto && ti > 0.5 && ti < 7.5) {
        NSString *name = NSStringFromSelector(sel);
        if (MFContains(name, @[ @"story", @"Story", @"advance", @"Advance", @"bucket", @"Bucket", @"progress", @"Progress" ])) {
            return %orig(60 * 60 * 24, target, sel, ui, NO);
        }
    }
    return %orig;
}
%end

%ctor {
    gCapturedURLs = [NSMutableArray array];
    MFLoadPrefs();
    if (![[NSFileManager defaultManager] fileExistsAtPath:kPrefsPath]) MFSavePrefs();
    NSLog(@"[MooDfacebook] v0.3.0 loaded — AVPlayer hooked, long-press tab for settings");
}
