#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.modyiq.moodfacebook.plist";
static const NSInteger kDLBtnTag   = 777001;

static BOOL gEnabled              = YES;
static BOOL gRemoveAds            = YES;
static BOOL gRemovePYMK           = YES;
static BOOL gRemoveReelsCarousel  = YES;
static BOOL gConfirmPostLike      = YES;
static BOOL gDownloadMedia        = YES;
static BOOL gReelsDownloadBtn     = YES;
static BOOL gReelsHideOverlay     = NO;
static BOOL gConfirmReelsLike     = YES;
static BOOL gReelsLongPressDL     = YES;
static BOOL gStoriesDownload      = YES;
static BOOL gStoriesAnon          = YES;
static BOOL gStoriesManualSeen    = YES;
static BOOL gStoriesNoAuto        = YES;
static BOOL gConfirmingLike       = NO;

static UIWindow *gSettingsWindow  = nil;

@interface MFVideoURL : NSObject
@property (nonatomic, strong) NSURL    *url;
@property (nonatomic, copy)   NSString *quality;
@property (nonatomic, assign) NSInteger byteSize;
@end
@implementation MFVideoURL
@end

static NSMutableArray<MFVideoURL *> *gVideoURLs = nil;
static dispatch_queue_t gURLQueue;

static NSString *MFGuessQuality(NSURL *url, long long contentLength) {
    NSString *s = url.absoluteString.lowercaseString;
    if ([s containsString:@"_n_1080"]) return @"1080p";
    if ([s containsString:@"_n_960"])  return @"960p";
    if ([s containsString:@"_n_720"])  return @"720p";
    if ([s containsString:@"_n_540"])  return @"540p";
    if ([s containsString:@"_n_480"])  return @"480p";
    if ([s containsString:@"_n_360"])  return @"360p";
    if ([s containsString:@"1080"])    return @"1080p";
    if ([s containsString:@"720"])     return @"720p";
    if ([s containsString:@"480"])     return @"480p";
    if ([s containsString:@"360"])     return @"360p";
    if (contentLength > 30000000) return @"1080p";
    if (contentLength > 15000000) return @"720p";
    if (contentLength > 7000000)  return @"480p";
    if (contentLength > 2000000)  return @"360p";
    if (contentLength > 0)        return @"Low";
    return @"Unknown";
}

static BOOL MFIsVideoURL(NSURL *url) {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme hasPrefix:@"http"]) return NO;
    NSString *s = url.absoluteString.lowercaseString;
    BOOL isFBCDN = [s containsString:@"fbcdn"] ||
                   [s containsString:@"facebook.com/video"] ||
                   [s containsString:@"video.f"] ||
                   [s containsString:@"video-"];
    BOOL isVideo = [s containsString:@".mp4"] ||
                   [s containsString:@".m3u8"] ||
                   [s containsString:@"bytestart="] ||
                   [s containsString:@"_n_"] ||
                   [s containsString:@"efg="];
    return isFBCDN && isVideo;
}

static void MFCaptureVideoURL(NSURL *url, long long contentLength) {
    if (!MFIsVideoURL(url)) return;
    dispatch_async(gURLQueue, ^{
        for (MFVideoURL *v in gVideoURLs)
            if ([v.url.absoluteString isEqualToString:url.absoluteString]) return;
        MFVideoURL *item = [MFVideoURL new];
        item.url      = url;
        item.quality  = MFGuessQuality(url, contentLength);
        item.byteSize = (NSInteger)contentLength;
        [gVideoURLs insertObject:item atIndex:0];
        if (gVideoURLs.count > 30) [gVideoURLs removeLastObject];
        NSLog(@"[MooDfacebook] Captured %@ -> %@", item.quality, url.absoluteString);
    });
}

static void MFSavePrefs(void) {
    NSDictionary *d = @{
        @"enabled":             @(gEnabled),
        @"removeAds":           @(gRemoveAds),
        @"removePYMK":          @(gRemovePYMK),
        @"removeReelsCarousel": @(gRemoveReelsCarousel),
        @"confirmPostLike":     @(gConfirmPostLike),
        @"downloadMedia":       @(gDownloadMedia),
        @"reelsDownloadBtn":    @(gReelsDownloadBtn),
        @"reelsHideOverlay":    @(gReelsHideOverlay),
        @"confirmReelsLike":    @(gConfirmReelsLike),
        @"reelsLongPressDL":    @(gReelsLongPressDL),
        @"storiesDownload":     @(gStoriesDownload),
        @"storiesAnon":         @(gStoriesAnon),
        @"storiesManualSeen":   @(gStoriesManualSeen),
        @"storiesNoAuto":       @(gStoriesNoAuto),
    };
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[kPrefsPath stringByDeletingLastPathComponent]
    withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:kPrefsPath atomically:YES];
}

static void MFLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!d) return;
    id v;
    v = d[@"enabled"];             if (v) gEnabled             = [v boolValue];
    v = d[@"removeAds"];           if (v) gRemoveAds           = [v boolValue];
    v = d[@"removePYMK"];          if (v) gRemovePYMK          = [v boolValue];
    v = d[@"removeReelsCarousel"]; if (v) gRemoveReelsCarousel = [v boolValue];
    v = d[@"confirmPostLike"];     if (v) gConfirmPostLike     = [v boolValue];
    v = d[@"downloadMedia"];       if (v) gDownloadMedia       = [v boolValue];
    v = d[@"reelsDownloadBtn"];    if (v) gReelsDownloadBtn    = [v boolValue];
    v = d[@"reelsHideOverlay"];    if (v) gReelsHideOverlay    = [v boolValue];
    v = d[@"confirmReelsLike"];    if (v) gConfirmReelsLike    = [v boolValue];
    v = d[@"reelsLongPressDL"];    if (v) gReelsLongPressDL    = [v boolValue];
    v = d[@"storiesDownload"];     if (v) gStoriesDownload     = [v boolValue];
    v = d[@"storiesAnon"];         if (v) gStoriesAnon         = [v boolValue];
    v = d[@"storiesManualSeen"];   if (v) gStoriesManualSeen   = [v boolValue];
    v = d[@"storiesNoAuto"];       if (v) gStoriesNoAuto       = [v boolValue];
}

static NSArray *MFWindows(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]])
            [a addObjectsFromArray:((UIWindowScene *)s).windows];
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

static void MFToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = MFKeyWindow();
        if (!w) return;
        UILabel *lab        = [[UILabel alloc] init];
        lab.text            = msg;
        lab.textColor       = UIColor.whiteColor;
        lab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
        lab.font            = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        lab.textAlignment   = NSTextAlignmentCenter;
        lab.numberOfLines   = 0;
        lab.layer.cornerRadius = 12;
        lab.clipsToBounds   = YES;
        CGFloat width = w.bounds.size.width - 48;
        CGSize sz = [lab sizeThatFits:CGSizeMake(width, 120)];
        lab.frame = CGRectMake(24, w.bounds.size.height - 160,
                               width, MAX(40, sz.height + 16));
        [w addSubview:lab];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3
                             animations:^{ lab.alpha = 0; }
                             completion:^(BOOL f){ [lab removeFromSuperview]; }];
        });
    });
}

static BOOL MFContains(NSString *s, NSArray *needles) {
    if (!s.length) return NO;
    NSString *l = s.lowercaseString;
    for (NSString *n in needles)
        if ([l containsString:n.lowercaseString]) return YES;
    return NO;
}

static BOOL MFIsSponsored(NSString *s) {
    return MFContains(s, @[@"sponsored",@"مموّل",@"ممول",@"gesponsert",@"sponsorizzato",@"patrocinado"]);
}

static BOOL MFIsPYMK(NSString *s) {
    return MFContains(s, @[@"people you may know",@"أشخاص قد تعرفهم",@"suggested for you",@"مقترح لك"]);
}

static BOOL MFIsReelsLabel(NSString *s) {
    if (!s.length) return NO;
    NSString *t = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    return [t isEqualToString:@"reels"] || [t isEqualToString:@"ريلز"] || [t hasPrefix:@"reels "];
}

static BOOL MFIsLikeLabel(NSString *s) {
    return MFContains(s, @[@"like",@"أعجبني",@"اعجبني",@"j'aime",@"gefällt mir"]);
}

static BOOL MFScanLabels(UIView *view, int depth, BOOL(*check)(NSString *)) {
    if (!view || depth > 9) return NO;
    if ([view isKindOfClass:[UILabel class]] && check(((UILabel *)view).text)) return YES;
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)view;
        if (check([b titleForState:UIControlStateNormal])) return YES;
        if (check(b.accessibilityLabel)) return YES;
    }
    if (check(view.accessibilityLabel)) return YES;
    for (UIView *sub in view.subviews)
        if (MFScanLabels(sub, depth+1, check)) return YES;
    return NO;
}

static void MFCollapse(UIView *v) {
    if (!v) return;
    v.hidden = YES; v.alpha = 0;
    CGRect f = v.frame; f.size.height = 0; v.frame = f;
}

static void MFSaveURLToPhotos(NSURL *url, NSString *quality) {
    NSString *label = quality.length
        ? [NSString stringWithFormat:@"Downloading %@...", quality]
        : @"Downloading...";
    MFToast(label);
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                               handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) {
            MFToast(@"Photos access denied"); return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
       forHTTPHeaderField:@"User-Agent"];
            [req setValue:@"https://www.facebook.com/" forHTTPHeaderField:@"Referer"];
            __block NSData *data = nil;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [[[NSURLSession sharedSession] dataTaskWithRequest:req
                completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                    data = d; dispatch_semaphore_signal(sem);
                }] resume];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120*NSEC_PER_SEC));
            if (!data.length) { MFToast(@"Download failed"); return; }
            NSString *ext = url.pathExtension.lowercaseString;
            if (!ext.length || ext.length > 4) ext = @"mp4";
            BOOL isImg = [@[@"jpg",@"jpeg",@"png",@"heic",@"webp"] containsObject:ext];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"mf_%@.%@", NSUUID.UUID.UUIDString, isImg?@"jpg":@"mp4"]];
            [data writeToFile:tmp atomically:YES];
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                NSURL *fu = [NSURL fileURLWithPath:tmp];
                if (isImg) [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:fu];
                else       [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fu];
            } completionHandler:^(BOOL ok, NSError *err) {
                [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
                MFToast(ok ? @"Saved to Photos!" : @"Save failed");
            }];
        });
    }];
}

static void MFShowQualityPicker(void) {
    __block NSArray<MFVideoURL *> *urls;
    dispatch_sync(gURLQueue, ^{ urls = [gVideoURLs copy]; });
    if (!urls.count) { MFToast(@"No video found — play it first"); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *sheet = [UIAlertController
            alertControllerWithTitle:@"MooDfacebook"
                             message:@"Choose quality"
                      preferredStyle:UIAlertControllerStyleActionSheet];
        for (MFVideoURL *item in urls) {
            NSString *title = item.byteSize > 0
                ? [NSString stringWithFormat:@"%@  (%.1f MB)", item.quality, item.byteSize/1048576.0]
                : item.quality;
            [sheet addAction:[UIAlertAction actionWithTitle:title
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *a) {
                MFSaveURLToPhotos(item.url, item.quality);
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel handler:nil]];
        [MFTopVC() presentViewController:sheet animated:YES completion:nil];
    });
}

static void MFDownload(void) {
    if (!gEnabled) return;
    MFShowQualityPicker();
}

@interface MFSettingsController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray     *sections;
@end

@implementation MFSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sections = @[
        @{ @"t": @"MAIN", @"r": @[
            @{ @"k": @"enabled",             @"l": @"Enable MooDfacebook" },
            @{ @"k": @"removeAds",           @"l": @"Remove Ads" },
            @{ @"k": @"removePYMK",          @"l": @"Remove People You May Know" },
            @{ @"k": @"removeReelsCarousel", @"l": @"Remove Reels Carousel" },
            @{ @"k": @"confirmPostLike",     @"l": @"Confirm Post Like" },
            @{ @"k": @"downloadMedia",       @"l": @"Download Videos",
               @"s": @"Long press on any video to download" },
        ]},
        @{ @"t": @"REELS", @"r": @[
            @{ @"k": @"reelsDownloadBtn",  @"l": @"Download Reels" },
            @{ @"k": @"reelsHideOverlay",  @"l": @"Hide Overlay" },
            @{ @"k": @"confirmReelsLike",  @"l": @"Confirm Reels Like" },
            @{ @"k": @"reelsLongPressDL",  @"l": @"Download via Long Press" },
        ]},
        @{ @"t": @"STORIES", @"r": @[
            @{ @"k": @"storiesDownload",   @"l": @"Download Stories" },
            @{ @"k": @"storiesAnon",       @"l": @"Watch Anonymously" },
            @{ @"k": @"storiesManualSeen", @"l": @"Manual Mark as Seen" },
            @{ @"k": @"storiesNoAuto",     @"l": @"Disable Auto-Advance" },
        ]},
    ];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,80)];
    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(0,16,self.view.bounds.size.width,44)];
    ttl.text = @"MooDfacebook";
    ttl.font = [UIFont boldSystemFontOfSize:20];
    ttl.textAlignment = NSTextAlignmentCenter;
    ttl.textColor = UIColor.labelColor;
    [header addSubview:ttl];
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width-50, 16, 44, 44);
    [closeBtn setTitle:@"X" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate   = self;
    self.table.tableHeaderView = header;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor    constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor  constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self.sections[s][@"r"] count]; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return self.sections[s][@"t"]; }
- (BOOL)valueForKey2:(NSString *)key {
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
- (void)setVal:(BOOL)on forKey2:(NSString *)key {
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
    NSDictionary *row = self.sections[ip.section][@"r"][ip.row];
    NSString *sub = row[@"s"];
    UITableViewCellStyle style = sub.length ? UITableViewCellStyleSubtitle : UITableViewCellStyleDefault;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:@"c"];
    cell.textLabel.text = row[@"l"];
    cell.detailTextLabel.text = sub;
    cell.detailTextLabel.numberOfLines = 2;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on  = [self valueForKey2:row[@"k"]];
    sw.tag = ip.section * 100 + ip.row;
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}
- (void)toggle:(UISwitch *)sw {
    NSString *key = self.sections[sw.tag/100][@"r"][sw.tag%100][@"k"];
    [self setVal:sw.on forKey2:key];
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
    if (!scene)
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;
    gSettingsWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gSettingsWindow.windowLevel        = UIWindowLevelAlert + 20;
    gSettingsWindow.rootViewController = [[MFSettingsController alloc] init];
    gSettingsWindow.frame              = scene.coordinateSpace.bounds;
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
    static MFActionTarget *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [MFActionTarget new]; });
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
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                           UIViewAutoresizingFlexibleTopMargin  |
                           UIViewAutoresizingFlexibleBottomMargin;
    btn.backgroundColor    = [UIColor colorWithWhite:0 alpha:0.6];
    btn.layer.cornerRadius = 23;
    [btn setTitle:@"v" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [btn addTarget:[MFActionTarget shared] action:@selector(download)
  forControlEvents:UIControlEventTouchUpInside];
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

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))ch {
    MFCaptureVideoURL(request.URL, 0);
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))ch {
    MFCaptureVideoURL(url, 0);
    return %orig;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))ch {
    MFCaptureVideoURL(request.URL, 0);
    return %orig;
}

%end

%hook NSHTTPURLResponse

- (instancetype)initWithURL:(NSURL *)url
                 statusCode:(NSInteger)statusCode
                HTTPVersion:(NSString *)HTTPVersion
               headerFields:(NSDictionary *)headerFields {
    self = %orig;
    if (self && MFIsVideoURL(url)) {
        NSString *cl = headerFields[@"Content-Length"] ?: headerFields[@"content-length"] ?: @"0";
        MFCaptureVideoURL(url, [cl longLongValue]);
    }
    return self;
}

%end

%hook AVPlayer

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item) {
        AVAsset *a = item.asset;
        if ([a isKindOfClass:[AVURLAsset class]])
            MFCaptureVideoURL(((AVURLAsset *)a).URL, 0);
    }
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = %orig;
    if (URL) MFCaptureVideoURL(URL, 0);
    return self;
}

%end

%hook UICollectionViewCell

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 48) return;
    if (gRemoveAds && MFScanLabels(self, 0, MFIsSponsored)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemovePYMK && MFScanLabels(self, 0, MFIsPYMK)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemoveReelsCarousel && MFScanLabels(self, 0, MFIsReelsLabel)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
}

%end

%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    if (self.bounds.size.height < 40) return;
    if (gRemoveAds && MFScanLabels(self, 0, MFIsSponsored)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
    if (gRemovePYMK && MFScanLabels(self, 0, MFIsPYMK)) {
        MFCollapse(self); self.contentView.hidden = YES; return;
    }
}

%end

%hook UICollectionView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled || !gRemoveReelsCarousel) return;
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width;
    if (h > 120 && h < 340 && w > h && MFScanLabels(self, 0, MFIsReelsLabel))
        MFCollapse(self);
}

%end

%hook UIControl

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (gConfirmingLike) { %orig; return; }
    if (gEnabled) {
        NSString *label = self.accessibilityLabel;
        if ([self isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)self;
            if (!label.length) label = [b titleForState:UIControlStateNormal];
            if (!label.length) label = b.titleLabel.text;
        }
        if (MFIsLikeLabel(label)) {
            CGRect f = [self convertRect:self.bounds toView:nil];
            BOOL nearBottom  = f.origin.y > UIScreen.mainScreen.bounds.size.height * 0.55;
            BOOL needConfirm = nearBottom ? gConfirmReelsLike : gConfirmPostLike;
            if (needConfirm) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"MooDfacebook"
                                     message:@"Confirm like?"
                              preferredStyle:UIAlertControllerStyleAlert];
                __weak UIControl *ws = self;
                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                          style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Like"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *a) {
                    gConfirmingLike = YES;
                    [ws sendAction:action to:target forEvent:event];
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
    CGFloat h = self.view.bounds.size.height, w = self.view.bounds.size.width;
    if (h > 500 && w > 280) {
        if (gReelsDownloadBtn) MFEnsureDLButton(self.view);
        if (gDownloadMedia || gReelsLongPressDL || gStoriesDownload)
            MFAttachLongPress(self.view);
        if (gReelsHideOverlay) {
            for (UIView *sub in self.view.subviews) {
                if (sub.tag == kDLBtnTag) continue;
                CGRect f = sub.frame;
                if ((f.origin.y > h*0.65 && f.size.height < h*0.4) ||
                    (f.origin.x > w*0.7  && f.size.width  < w*0.35)) {
                    sub.alpha = 0.08;
                    sub.userInteractionEnabled = NO;
                }
            }
        }
    }
}

%end

%hook NSTimer

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)target
                                   selector:(SEL)sel
                                   userInfo:(id)ui
                                    repeats:(BOOL)rep {
    if (gEnabled && gStoriesNoAuto && ti > 0.5 && ti < 7.5) {
        NSString *name = NSStringFromSelector(sel);
        if (MFContains(name, @[@"story",@"Story",@"advance",@"Advance",
                               @"bucket",@"Bucket",@"progress",@"Progress"]))
            return %orig(60*60*24, target, sel, ui, NO);
    }
    return %orig;
}

%end

%ctor {
    gURLQueue  = dispatch_queue_create("com.modyiq.moodfacebook.urls", DISPATCH_QUEUE_SERIAL);
    gVideoURLs = [NSMutableArray array];
    MFLoadPrefs();
    if (![[NSFileManager defaultManager] fileExistsAtPath:kPrefsPath]) MFSavePrefs();
    NSLog(@"[MooDfacebook] v0.4.0 loaded");
}
