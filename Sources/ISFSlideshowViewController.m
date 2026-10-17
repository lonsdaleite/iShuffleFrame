#import "ISFSlideshowViewController.h"
#import "ISFCycleStore.h"
#import "ISFImageLoader.h"

static const NSTimeInterval ISFFadeDuration = 0.8;
static const NSTimeInterval ISFSlideDuration = 0.3;
/// Pause before trying the next photo when one fails to load.
static const NSTimeInterval ISFSkipDelay = 0.5;
/// A photo that has not loaded by then (e.g. a stalled iCloud download) counts as failed.
static const NSTimeInterval ISFLoadTimeout = 60;
/// After this many failures in a row the slideshow stops skipping and retries the same photo every interval,
/// so that a short iCloud outage does not use up the cycle.
static const NSUInteger ISFMaxSkips = 5;
/// In retry mode a photo is retried this many times before the slideshow moves on (it may be broken for good).
static const NSUInteger ISFMaxRetries = 3;
/// The pause menu closes itself after this long, so that a stray tap does not stop the frame for the day.
static const NSTimeInterval ISFPauseMenuTimeout = 120;
/// Photos loaded ahead of the current one, so that swipes and slow iCloud downloads do not keep the frame waiting.
static const NSUInteger ISFPrefetchCount = 3;
/// Decoded photos kept in memory: the prefetched ones, the current one and a few before it for swiping back.
/// At most 12 MB each on a 2048 × 1536 screen.
static const NSUInteger ISFImageCacheSize = 7;
/// The cycle state is saved at most this often while photos change (and always on stop, backgrounding and
/// library changes); a killed app replays at most a few minutes of photos.
static const NSTimeInterval ISFSaveInterval = 300;

@implementation ISFSlideshowViewController {
    id<ISFPhotoSource> _source;
    ISFSettings *_settings;
    ISFCycle *_cycle;
    BOOL _running;
    BOOL _paused;
    NSTimer *_timer;
    NSUInteger _startToken;    // changes on every start/stop; stale item lists are dropped
    NSUInteger _requestToken;  // changes on every photo request; stale results are dropped
    NSUInteger _resolvedToken; // the last request that got an image, failed or timed out
    NSUInteger _failures;
    BOOL _retryCurrent;
    NSUInteger _retries;
    NSDictionary *_pendingState; // saved cycle waiting for a non-empty item list (library not ready yet)
    NSInteger _slide;          // +1/-1 while the photo for a swipe is loading, see showItem:animated:slide:
    NSInteger _direction;      // +1 forward, -1 back: where to skip a photo that fails to load
    NSString *_requestedItem;  // photo of the current request
    NSDate *_lastSave;

    dispatch_queue_t _itemsQueue; // item lists are fetched one at a time, in order
    _Atomic(NSUInteger) _itemsGeneration; // only the latest item list is fetched and applied
    BOOL _reloadPending;          // the library changed while the first item list was loading

    ISFImageLoader *_loader;

    UIImageView *_imageView;
    UILabel *_messageLabel;
    UIView *_pauseMenu;        // overlay over the photo while paused
    UIView *_pauseMenuPanel;
}

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _source = source;
        _settings = settings;
        _direction = 1;
        _itemsQueue = dispatch_queue_create("ishuffleframe.items", DISPATCH_QUEUE_SERIAL);
        _loader = [[ISFImageLoader alloc] initWithSource:source targetSize:[self targetPixelSize] capacity:ISFImageCacheSize];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(appDidBecomeActive)
                       name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(appWillResignActive)
                       name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(appDidEnterBackground)
                       name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(appWillEnterForeground)
                       name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.backgroundColor = [UIColor blackColor];
    _imageView.isAccessibilityElement = YES;
    _imageView.accessibilityIdentifier = @"ISFSlideshowImage";
#if DEBUG
    // Lets UI tests tell a relaunch from a running app.
    _imageView.accessibilityLabel = [NSString stringWithFormat:@"pid %d", [NSProcessInfo processInfo].processIdentifier];
#endif
    [self.view addSubview:_imageView];

    _messageLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 40, 40)];
    _messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _messageLabel.textColor = [UIColor lightGrayColor];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.numberOfLines = 0;
    _messageLabel.font = [UIFont systemFontOfSize:22];
    _messageLabel.accessibilityIdentifier = @"ISFSlideshowMessage";
    _messageLabel.hidden = YES;
    [self.view addSubview:_messageLabel];

    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedLeft)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedRight)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [self.view addGestureRecognizer:left];
    [self.view addGestureRecognizer:right];
    // A swipe also looks like a tap to the tap recognizer: open the menu only for touches that are not swipes.
    [tap requireGestureRecognizerToFail:left];
    [tap requireGestureRecognizerToFail:right];
    [self.view addGestureRecognizer:tap];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_loader trimExceptItem:_cycle.current];
}

#pragma mark - Control

- (BOOL)isRunning {
    return _running && !_paused;
}

- (void)start {
    [self stop];
    [self loadViewIfNeeded];

    if (!_settings.hasSource) {
        [self showMessage:@"Choose photos in Settings."];
        if (self.settingsHandler) self.settingsHandler();
        return;
    }

    ISFAuthorization authorization = [_source authorization];
    if (authorization == ISFAuthorizationNotDetermined) {
        [_source requestAuthorization:^(ISFAuthorization status) {
            // The user may have opened the settings meanwhile; they start the slideshow themselves.
            if (status != ISFAuthorizationNotDetermined && !self.presentedViewController) [self start];
        }];
        return;
    }
    if (authorization == ISFAuthorizationDenied) {
        [self showMessage:@"No access to Photos.\nAllow it in the Settings app: Privacy → Photos."];
        return;
    }

    __weak typeof(self) weakSelf = self;
    _source.changeHandler = ^{ [weakSelf sourceDidChange]; };
    _running = YES;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSDictionary *state = [ISFCycleStore loadState];
    ISFOrder order = _settings.order;
    NSUInteger token = _startToken;
    [self loadItems:^(NSArray<NSString *> *items) {
        if (token != self->_startToken) return;
        // An empty list right after launch may only mean the library is not ready: keep the saved cycle for later.
        self->_pendingState = items.count ? nil : state;
        self->_cycle = [ISFCycle cycleWithItems:items order:order state:items.count ? state : nil random:nil];
        self->_direction = 1;
        if (!self->_paused) [self showItem:[self->_cycle next] animated:NO];
        if (self->_reloadPending) [self sourceDidChange];
    }];
}

- (void)stop {
    if (_cycle) [self saveStateForced:YES];
    [self cancelRequests];
    _running = NO;
    _paused = NO;
    _cycle = nil;
    _startToken++;
    _requestToken++;
    _failures = 0;
    _retries = 0;
    _retryCurrent = NO;
    _pendingState = nil;
    [_timer invalidate];
    _timer = nil;
    _reloadPending = NO;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self menuClosed];
}

/// Fetches the item list off the main thread (it enumerates the whole library for All Photos).
/// Only the result of the latest call is delivered.
- (void)loadItems:(void (^)(NSArray<NSString *> *items))completion {
    id<ISFPhotoSource> source = _source;
    BOOL allPhotos = _settings.useAllPhotos;
    NSArray<NSString *> *albumIDs = _settings.albumIDs;
    NSUInteger generation = ++_itemsGeneration;
    dispatch_async(_itemsQueue, ^{
        if (generation != self->_itemsGeneration) return; // a newer request is queued: skip this enumeration
        NSArray<NSString *> *items = [source itemIDsForAllPhotos:allPhotos albumIDs:albumIDs];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self->_itemsGeneration) completion(items);
        });
    });
}

- (void)sourceDidChange {
    if (!_running) return;
    if (!_cycle) {
        _reloadPending = YES; // applied once the first item list is in
        return;
    }
    _reloadPending = NO;
    NSUInteger token = _startToken;
    [self loadItems:^(NSArray<NSString *> *items) {
        if (token != self->_startToken || !self->_cycle) return;
        ISFCycle *cycle = self->_cycle;
        if ([items isEqualToArray:cycle.items]) return; // a change elsewhere in the library
        // An empty list while photos were shown is most likely iCloud being briefly unavailable; keep the cycle.
        if (items.count == 0 && cycle.items.count > 0) return;
        BOOL wasEmpty = cycle.current == nil;
        if (cycle.items.count == 0 && self->_pendingState) {
            self->_cycle = [ISFCycle cycleWithItems:items order:cycle.order state:self->_pendingState random:nil];
            self->_pendingState = nil;
        } else {
            [cycle updateItems:items];
        }
        [self saveStateForced:YES];
        if (wasEmpty && !self->_paused) [self showItem:[self->_cycle next] animated:NO];
    }];
}

- (void)saveStateForced:(BOOL)forced {
    if (_cycle.items.count == 0) return; // never overwrite a saved cycle with an empty one
    if (!forced && _lastSave && -[_lastSave timeIntervalSinceNow] < ISFSaveInterval) return;
    _lastSave = [NSDate date];
    [ISFCycleStore save:[_cycle state]];
}

- (void)cancelRequests {
    [_loader reset];
}

#pragma mark - Showing photos

- (CGSize)targetPixelSize {
    // Photos are fitted into a square of the longer screen side, so rotation does not need a reload.
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat side = MAX(bounds.size.width, bounds.size.height) * [UIScreen mainScreen].scale;
    return CGSizeMake(side, side);
}

- (void)showItem:(NSString *)item animated:(BOOL)animated {
    [self showItem:item animated:animated slide:0];
}

/// `slide` is +1 or -1 when the photo is shown after a swipe: it slides in from that side whatever the transition.
- (void)showItem:(NSString *)item animated:(BOOL)animated slide:(NSInteger)slide {
    _slide = slide;
    [_timer invalidate];
    _timer = nil;
    _retryCurrent = NO;
    if (_requestedItem && _resolvedToken != _requestToken) [_loader stopWaitingForItem:_requestedItem];
    _requestedItem = item;
    NSUInteger token = ++_requestToken;

    if (!item) {
        _imageView.image = nil;
        _imageView.accessibilityValue = nil;
        [self showMessage:@"No photos in the selected albums."];
        return;
    }

    UIImage *cached = [_loader cachedImageForItem:item];
    if (cached) {
        _resolvedToken = token;
        [self displayImage:cached item:item animated:animated];
        return;
    }
    [_loader loadItem:item completion:^(UIImage *image) {
        [self request:token finishedWithImage:image item:item animated:animated];
    }];
    [self startWatchdogForToken:token];
}

- (void)request:(NSUInteger)token finishedWithImage:(UIImage *)image item:(NSString *)item animated:(BOOL)animated {
    if (token != _requestToken || token == _resolvedToken || !_running) return;
    _resolvedToken = token;
    if (image) {
        [self displayImage:image item:item animated:animated];
    } else {
        [self loadFailed];
    }
}

- (void)startWatchdogForToken:(NSUInteger)token {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ISFLoadTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self->_requestToken || token == self->_resolvedToken || !self->_running) return;
        self->_resolvedToken = token;
        [self loadFailed];
    });
}

- (void)displayImage:(UIImage *)image item:(NSString *)item animated:(BOOL)animated {
    _failures = 0;
    _messageLabel.hidden = YES;
    if (_slide) {
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionPush;
        transition.subtype = _slide > 0 ? kCATransitionFromRight : kCATransitionFromLeft;
        transition.duration = ISFSlideDuration;
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_imageView.layer addAnimation:transition forKey:@"slide"];
        _imageView.image = image;
        _slide = 0;
    } else if (animated && _settings.transition == ISFTransitionFade) {
        [UIView transitionWithView:_imageView
                          duration:ISFFadeDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ self->_imageView.image = image; }
                        completion:nil];
    } else {
        _imageView.image = image;
    }
    _imageView.accessibilityValue = item;
    _retries = 0;
    [self saveStateForced:NO];
    if (!_paused) [self scheduleTimer];
    [self prefetch];
}

- (void)loadFailed {
    if (_requestedItem) [_loader dropItem:_requestedItem]; // it may be stuck: a retry makes a new request
    _failures++;
    if (_failures >= ISFMaxSkips) {
        // Keep the last photo on screen and retry the current one every interval; give up on it after a few
        // retries, it may be broken for good.
        if (!_imageView.image) [self showMessage:@"Photos could not be loaded."];
        _retryCurrent = _retries < ISFMaxRetries;
        _retries = _retryCurrent ? _retries + 1 : 0;
        if (!_paused) [self scheduleTimer];
        return;
    }
    NSUInteger token = _requestToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ISFSkipDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self->_requestToken || !self->_running || self->_paused) return;
        [self skipInDirection];
    });
}

- (void)skipInDirection {
    if (_direction < 0) {
        NSString *previous = [_cycle previous];
        if (previous) {
            [self showItem:previous animated:NO];
            return;
        }
        _direction = 1;
    }
    [self showItem:[_cycle next] animated:NO];
}

- (void)prefetch {
    NSMutableArray<NSString *> *items = [[_cycle peekNext:ISFPrefetchCount] mutableCopy];
    NSString *previous = [_cycle peekPrevious];
    if (previous) [items addObject:previous];
    [_loader prefetchItems:items];
}

- (void)showMessage:(NSString *)message {
    _messageLabel.text = message;
    _messageLabel.hidden = NO;
}

- (void)scheduleTimer {
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_settings.interval
                                              target:self
                                            selector:@selector(timerFired)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)timerFired {
    _timer = nil;
    if (!_running || _paused || !_cycle) return;
    if (_retryCurrent && _cycle.current) {
        [self showItem:_cycle.current animated:YES];
        return;
    }
    _direction = 1;
    [self showItem:[_cycle next] animated:YES];
}

#pragma mark - Gestures

- (void)swipedLeft {
    if (!_running || _paused || !_cycle) return;
    _direction = 1;
    _failures = 0;
    [self showItem:[_cycle next] animated:NO slide:1];
}

- (void)swipedRight {
    if (!_running || _paused || !_cycle) return;
    NSString *item = [_cycle previous];
    if (!item) return;
    _direction = -1;
    _failures = 0;
    [self showItem:item animated:NO slide:-1];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (_pauseMenu) {
        // A tap next to the menu works like Resume.
        if (CGRectContainsPoint(_pauseMenuPanel.frame, [tap locationInView:_pauseMenu])) return;
        [self closeMenuResuming];
        return;
    }
    [self pause];
    [self showPauseMenu];

    // Nobody answered the menu: the tap was probably accidental.
    UIView *menu = _pauseMenu;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ISFPauseMenuTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ISFSlideshowViewController *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_pauseMenu == menu) [strongSelf closeMenuResuming];
    });
}

/// A dimmed overlay with Resume (when the slideshow runs) and Settings; see tapped: for taps next to it.
- (void)showPauseMenu {
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    overlay.accessibilityIdentifier = @"ISFPauseMenu";

    UIView *panel = [UIView new];
    panel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    panel.layer.cornerRadius = 14;
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                             UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    UILabel *title = [UILabel new];
    title.text = @"Paused";
    title.textColor = [UIColor lightGrayColor];
    title.font = [UIFont systemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [rows addObject:title];
    if (_running) [rows addObject:[self menuButtonWithTitle:@"Resume" action:@selector(closeMenuResuming)]];
    [rows addObject:[self menuButtonWithTitle:@"Settings" action:@selector(openSettingsFromMenu)]];

    const CGFloat width = 280, rowHeight = 56;
    panel.frame = CGRectMake(0, 0, width, rowHeight * rows.count);
    for (NSUInteger i = 0; i < rows.count; i++) {
        rows[i].frame = CGRectMake(0, rowHeight * i, width, rowHeight);
        [panel addSubview:rows[i]];
    }
    panel.center = CGPointMake(CGRectGetMidX(overlay.bounds), CGRectGetMidY(overlay.bounds));
    [overlay addSubview:panel];

    _pauseMenu = overlay;
    _pauseMenuPanel = panel;
    overlay.alpha = 0;
    [self.view addSubview:overlay];
    [UIView animateWithDuration:0.2 animations:^{ overlay.alpha = 1; }];
}

- (UIButton *)menuButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)closeMenuResuming {
    if (_running) {
        [self resume];
    } else {
        [self menuClosed];
    }
}

- (void)openSettingsFromMenu {
    [self stop];
    if (self.settingsHandler) self.settingsHandler();
}

- (void)menuClosed {
    [_pauseMenu removeFromSuperview];
    _pauseMenu = nil;
    _pauseMenuPanel = nil;
}

- (void)pause {
    if (!_running) return;
    _paused = YES;
    [_timer invalidate];
    _timer = nil;
    // The screen stays on while the pause menu is open: an auto-lock before the menu times out would leave
    // the frame paused and dark.
}

- (void)resume {
    [self menuClosed];
    if (!_running) return;
    _paused = NO;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    if (!_cycle) return; // still loading the item list; it shows the first photo itself
    if (_cycle.current && _resolvedToken == _requestToken) {
        [self scheduleTimer];
    } else {
        [self showItem:_cycle.current ?: [_cycle next] animated:NO];
    }
}

#pragma mark - App state

// The slideshow keeps going while the app is only inactive (Control Center, an alert, a screen turned off and on
// without locking): it stops in the background, and nothing guarantees a didBecomeActive after a resign.

- (void)appWillResignActive {
    // Scripts lock the device and kill the app right after: write before going on.
    if (_cycle.items.count) {
        _lastSave = [NSDate date];
        [ISFCycleStore saveNow:[_cycle state]];
    }
}

- (void)appDidEnterBackground {
    [_timer invalidate];
    _timer = nil;
}

- (void)appWillEnterForeground {
    [self resumeTimerIfNeeded];
}

- (void)appDidBecomeActive {
    [self resumeTimerIfNeeded];
}

- (void)resumeTimerIfNeeded {
    if (_running && !_paused && _cycle.current && !_timer && _resolvedToken == _requestToken) [self scheduleTimer];
}

@end
