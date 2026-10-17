#import "ISFAlbumPickerViewController.h"

@implementation ISFAlbumPickerViewController {
    id<ISFPhotoSource> _source;
    ISFSettings *_settings;
    NSArray<NSString *> *_sectionTitles;
    NSArray<NSArray<ISFAlbum *> *> *_sections;
    NSMutableOrderedSet<NSString *> *_selected;
    NSString *_message;
}

- (instancetype)initWithSource:(id<ISFPhotoSource>)source settings:(ISFSettings *)settings {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _source = source;
        _settings = settings;
        _selected = [NSMutableOrderedSet orderedSetWithArray:settings.albumIDs];
        _sections = @[];
        _sectionTitles = @[];
        self.title = @"Albums";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    ISFAuthorization authorization = [_source authorization];
    if (authorization == ISFAuthorizationNotDetermined) {
        [_source requestAuthorization:^(ISFAuthorization status) { [self reloadAlbums]; }];
    } else {
        [self reloadAlbums];
    }
}

- (void)reloadAlbums {
    if ([_source authorization] != ISFAuthorizationAuthorized) {
        _message = @"No access to Photos. Allow it in the Settings app: Privacy → Photos.";
        _sections = @[];
        _sectionTitles = @[];
        [self.tableView reloadData];
        return;
    }

    NSArray<ISFAlbum *> *albums = [_source albums];

    NSArray<NSNumber *> *kinds = @[@(ISFAlbumKindShared), @(ISFAlbumKindRegular), @(ISFAlbumKindOther), @(ISFAlbumKindSmart)];
    NSDictionary<NSNumber *, NSString *> *names = @{@(ISFAlbumKindShared): @"Shared Albums",
                                                   @(ISFAlbumKindRegular): @"My Albums",
                                                   @(ISFAlbumKindOther): @"Other Albums",
                                                   @(ISFAlbumKindSmart): @"Smart Albums"};
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *kind in kinds) {
        NSPredicate *byKind = [NSPredicate predicateWithBlock:^BOOL(ISFAlbum *album, NSDictionary *bindings) {
            return album.kind == kind.integerValue;
        }];
        NSArray<ISFAlbum *> *matching = [albums filteredArrayUsingPredicate:byKind];
        if (matching.count == 0) continue;
        [sections addObject:matching];
        [titles addObject:names[kind]];
    }
    // Selected albums that are not in the library now: deleted, left, still syncing, or an empty smart album.
    // They stay selected (they may come back) and are listed so that they can be unticked.
    NSSet<NSString *> *existing = [NSSet setWithArray:[albums valueForKey:@"identifier"]];
    NSMutableArray<ISFAlbum *> *unavailable = [NSMutableArray array];
    for (NSString *identifier in _selected) {
        if ([existing containsObject:identifier]) continue;
        ISFAlbum *album = [ISFAlbum new];
        album.identifier = identifier;
        album.title = @"Unavailable Album";
        album.kind = ISFAlbumKindOther;
        [unavailable addObject:album];
    }
    if (unavailable.count) {
        [sections addObject:unavailable];
        [titles addObject:@"Unavailable"];
    }
    _sections = sections;
    _sectionTitles = titles;
    _message = albums.count ? nil : @"There are no albums on this device.";
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _message ? (NSInteger)_sections.count + 1 : (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section >= (NSInteger)_sections.count) return 0;
    return (NSInteger)_sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section < (NSInteger)_sectionTitles.count ? _sectionTitles[section] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section >= (NSInteger)_sections.count ? _message : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ISFAlbum *album = _sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = album.title;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)album.count];
    cell.accessibilityIdentifier = [@"ISFAlbum-" stringByAppendingString:album.title];
    cell.accessoryType = [_selected containsObject:album.identifier] ? UITableViewCellAccessoryCheckmark
                                                                     : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ISFAlbum *album = _sections[indexPath.section][indexPath.row];
    if ([_selected containsObject:album.identifier]) {
        [_selected removeObject:album.identifier];
    } else {
        [_selected addObject:album.identifier];
    }
    _settings.albumIDs = _selected.array;
    _settings.useAllPhotos = NO;
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

@end
