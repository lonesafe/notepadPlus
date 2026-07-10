#import <Cocoa/Cocoa.h>

@class NppMacTabBarView;

@interface NppMacTabItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *toolTip;
@property(nonatomic) BOOL dirty;
@end

@protocol NppMacTabBarViewDelegate <NSObject>
- (void)tabBarView:(NppMacTabBarView *)tabBar didSelectTabAtIndex:(NSUInteger)index;
- (void)tabBarView:(NppMacTabBarView *)tabBar didRequestCloseTabAtIndex:(NSUInteger)index;
- (void)tabBarViewDidRequestNewTab:(NppMacTabBarView *)tabBar;
- (void)tabBarView:(NppMacTabBarView *)tabBar
	didMoveTabFromIndex:(NSUInteger)sourceIndex
	toIndex:(NSUInteger)destinationIndex;
@end

@interface NppMacTabBarView : NSView
@property(nonatomic, weak) id<NppMacTabBarViewDelegate> delegate;
@property(nonatomic, copy) NSArray<NppMacTabItem *> *items;
@property(nonatomic) NSInteger selectedIndex;
@end
