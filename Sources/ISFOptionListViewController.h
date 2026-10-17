#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A list of options with a checkmark on the selected one. Picking an option calls the handler and goes back.
@interface ISFOptionListViewController : UITableViewController

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles selectedIndex:(NSUInteger)selectedIndex NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, copy, nullable) void (^selectionHandler)(NSUInteger index);

@end

NS_ASSUME_NONNULL_END
