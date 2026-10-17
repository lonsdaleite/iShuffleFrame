#import "ISFSettingsViewController.h"
#import "ISFAlbumPickerViewController.h"
#import "ISFOptionListViewController.h"

typedef NS_ENUM(NSInteger, ISFSection) {
    ISFSectionSource = 0,
    ISFSectionOrder,
    ISFSectionTiming,
    ISFSectionTransition,
    ISFSectionAutostart,
    ISFSectionStart,
    ISFSectionCount,
};

static NSString *ISFIntervalLabel(NSTimeInterval seconds) {
    NSInteger value = (NSInteger)seconds;
    if (value < 60) return [NSString stringWithFormat:@"%ld s", (long)value];
    if (value < 3600) {
        return value % 60 ? [NSString stringWithFormat:@"%ld min %ld s", (long)(value / 60), (long)(value % 60)]
                          : [NSString stringWithFormat:@"%ld min", (long)(value / 60)];
    }
    return [NSString stringWithFormat:@"%ld h", (long)(value / 3600)];
}

@implementation ISFSettingsViewController {
    id<ISFPhotoSource> _source;
    ISFSettings *_settings;
}

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _source = source;
        _settings = settings;
        self.title = @"iShuffleFrame";
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ISFSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case ISFSectionSource: return 2;
        case ISFSectionOrder: return 2;
        case ISFSectionTiming: return 1;
        case ISFSectionTransition: return 2;
        case ISFSectionAutostart: return 1;
        case ISFSectionStart: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case ISFSectionSource: return @"Photos";
        case ISFSectionOrder: return @"Order";
        case ISFSectionTiming: return @"Timing";
        case ISFSectionTransition: return @"Transition";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case ISFSectionSource:
            return @"All Photos is the photo library on this device. iCloud shared albums are not part of it; "
                   @"pick them under Albums.";
        case ISFSectionAutostart:
            return @"Start the slideshow right away when the app opens. ishuffleframe://start starts it from "
                   @"other apps and scripts. The slideshow continues its cycle after a relaunch.";
        case ISFSectionStart: {
            NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
            return version ? [NSString stringWithFormat:@"Version %@", version] : nil;
        }
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSInteger row = indexPath.row;
    switch (indexPath.section) {
        case ISFSectionSource:
            if (row == 0) {
                cell.textLabel.text = @"All Photos";
                cell.accessibilityIdentifier = @"ISFAllPhotosCell";
                cell.accessoryType = _settings.useAllPhotos ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            } else {
                NSUInteger count = _settings.albumIDs.count;
                cell.textLabel.text = @"Albums";
                if (_settings.useAllPhotos) {
                    cell.detailTextLabel.text = @"Off";
                } else {
                    cell.detailTextLabel.text = count ? [NSString stringWithFormat:@"%lu selected", (unsigned long)count] : @"None";
                }
                cell.accessibilityIdentifier = @"ISFAlbumsCell";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        case ISFSectionOrder: {
            BOOL shuffle = row == 0;
            cell.textLabel.text = shuffle ? @"Shuffle" : @"In Order";
            cell.accessibilityIdentifier = shuffle ? @"ISFShuffleCell" : @"ISFSequentialCell";
            ISFOrder order = shuffle ? ISFOrderShuffle : ISFOrderSequential;
            cell.accessoryType = _settings.order == order ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        case ISFSectionTiming:
            cell.textLabel.text = @"Show Each Photo";
            cell.detailTextLabel.text = ISFIntervalLabel(_settings.interval);
            cell.accessibilityIdentifier = @"ISFIntervalCell";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case ISFSectionTransition: {
            BOOL none = row == 0;
            cell.textLabel.text = none ? @"None" : @"Fade";
            cell.accessibilityIdentifier = none ? @"ISFTransitionNoneCell" : @"ISFTransitionFadeCell";
            ISFTransition transition = none ? ISFTransitionNone : ISFTransitionFade;
            cell.accessoryType = _settings.transition == transition ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        case ISFSectionAutostart: {
            cell.textLabel.text = @"Start on Launch";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new];
            toggle.on = _settings.autostart;
            toggle.accessibilityIdentifier = @"ISFAutostartSwitch";
            [toggle addTarget:self action:@selector(autostartChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case ISFSectionStart: {
            BOOL enabled = _settings.hasSource;
            cell.textLabel.text = @"Start Slideshow";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = enabled ? self.view.tintColor : [UIColor lightGrayColor];
            cell.accessibilityIdentifier = @"ISFStartCell";
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger row = indexPath.row;
    switch (indexPath.section) {
        case ISFSectionSource:
            if (row == 0) {
                _settings.useAllPhotos = YES;
                [self requestAccessIfNeeded];
                [tableView reloadData];
            } else {
                [self openAlbums];
            }
            break;
        case ISFSectionOrder:
            _settings.order = row == 0 ? ISFOrderShuffle : ISFOrderSequential;
            [tableView reloadData];
            break;
        case ISFSectionTiming:
            [self openIntervals];
            break;
        case ISFSectionTransition:
            _settings.transition = row == 0 ? ISFTransitionNone : ISFTransitionFade;
            [tableView reloadData];
            break;
        case ISFSectionStart:
            if (_settings.hasSource && self.startHandler) self.startHandler();
            break;
    }
}

#pragma mark - Actions

- (void)autostartChanged:(UISwitch *)toggle {
    _settings.autostart = toggle.on;
}

- (void)requestAccessIfNeeded {
    if ([_source authorization] == ISFAuthorizationNotDetermined) {
        [_source requestAuthorization:^(ISFAuthorization status) {}];
    }
}

- (void)openAlbums {
    ISFAlbumPickerViewController *picker = [[ISFAlbumPickerViewController alloc] initWithSource:_source settings:_settings];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)openIntervals {
    NSArray<NSNumber *> *values = @[@3, @5, @10, @15, @20, @30, @45, @60, @90, @120, @180, @300, @600, @900, @1800, @3600];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:values.count];
    NSUInteger selected = NSNotFound;
    for (NSUInteger i = 0; i < values.count; i++) {
        [titles addObject:ISFIntervalLabel(values[i].doubleValue)];
        if (values[i].doubleValue == _settings.interval) selected = i;
    }
    ISFSettings *settings = _settings;
    ISFOptionListViewController *list = [[ISFOptionListViewController alloc] initWithTitles:titles selectedIndex:selected];
    list.title = @"Show Each Photo";
    list.selectionHandler = ^(NSUInteger index) { settings.interval = values[index].doubleValue; };
    [self.navigationController pushViewController:list animated:YES];
}

@end
