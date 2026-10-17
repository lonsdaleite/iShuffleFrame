#import "ISFOptionListViewController.h"

@implementation ISFOptionListViewController {
    NSArray<NSString *> *_titles;
    NSUInteger _selectedIndex;
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSUInteger)selectedIndex {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _titles = [titles copy];
        _selectedIndex = selectedIndex;
    }
    return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_titles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = _titles[indexPath.row];
    cell.accessoryType = (NSUInteger)indexPath.row == _selectedIndex ? UITableViewCellAccessoryCheckmark
                                                                      : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    _selectedIndex = (NSUInteger)indexPath.row;
    if (self.selectionHandler) self.selectionHandler(_selectedIndex);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
