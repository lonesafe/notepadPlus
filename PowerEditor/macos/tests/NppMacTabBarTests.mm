#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacTabBarView.h"

@interface NppMacTabBarTestDelegate : NSObject <NppMacTabBarViewDelegate>
@property(nonatomic) NSUInteger newTabRequestCount;
@end

@implementation NppMacTabBarTestDelegate
- (void)tabBarView:(NppMacTabBarView *)tabBar didSelectTabAtIndex:(NSUInteger)index {
	(void)tabBar;
	(void)index;
}
- (void)tabBarView:(NppMacTabBarView *)tabBar didRequestCloseTabAtIndex:(NSUInteger)index {
	(void)tabBar;
	(void)index;
}
- (void)tabBarViewDidRequestNewTab:(NppMacTabBarView *)tabBar {
	(void)tabBar;
	self.newTabRequestCount++;
}
- (void)tabBarView:(NppMacTabBarView *)tabBar
	didMoveTabFromIndex:(NSUInteger)sourceIndex
	toIndex:(NSUInteger)destinationIndex {
	(void)tabBar;
	(void)sourceIndex;
	(void)destinationIndex;
}
@end

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

static NppMacTabItem *item(NSString *title, BOOL dirty) {
	NppMacTabItem *value = [[NppMacTabItem alloc] init];
	value.title = title;
	value.toolTip = [@"/tmp/" stringByAppendingString:title];
	value.dirty = dirty;
	return value;
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		NppMacTabBarView *tabBar = [[NppMacTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 300, 32)];
		tabBar.items = @[
			item(@"first.cpp", NO),
			item(@"a-very-long-source-file-name-that-needs-truncation.cpp", YES),
			item(@"third.txt", NO)
		];
		tabBar.selectedIndex = 1;
		[tabBar layoutSubtreeIfNeeded];

		NSView *strip = [tabBar valueForKey:@"stripView"];
		NSArray<NSValue *> *rects = [strip valueForKey:@"tabRects"];
		require(rects.count == 3, "tab strip should create one rectangle per document");
		require([[strip valueForKey:@"selectedIndex"] integerValue] == 1,
			"selection should be forwarded to the custom strip");
		require(NSWidth(rects[0].rectValue) >= 110.0, "short tabs should keep the original-style minimum width");
		require(NSWidth(rects[1].rectValue) <= 240.0, "long tabs should be capped and rendered with truncation");
		require(NSMinX(rects[1].rectValue) == NSMaxX(rects[0].rectValue),
			"tab rectangles should be contiguous");
		NSRect newTabRect = [[strip valueForKey:@"newTabRect"] rectValue];
		require(NSMinX(newTabRect) == NSMaxX(rects.lastObject.rectValue),
			"new-tab button should immediately follow the final document tab");
		require(NSWidth(newTabRect) == 32.0 && NSHeight(newTabRect) == 32.0,
			"new-tab button should have a stable square hit target");

		NSButton *leftButton = [tabBar valueForKey:@"scrollLeftButton"];
		NSButton *rightButton = [tabBar valueForKey:@"scrollRightButton"];
		require(!leftButton.hidden && !rightButton.hidden,
			"overflow controls should appear when tabs exceed the available width");
		require(leftButton.enabled && rightButton.enabled,
			"revealing the selected middle tab should allow scrolling in both directions");

		NppMacTabBarView *clickTabBar = [[NppMacTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 400, 32)];
		NppMacTabBarTestDelegate *delegate = [[NppMacTabBarTestDelegate alloc] init];
		clickTabBar.delegate = delegate;
		clickTabBar.items = @[item(@"click-test.cpp", NO)];
		[clickTabBar layoutSubtreeIfNeeded];
		NSView *clickStrip = [clickTabBar valueForKey:@"stripView"];
		NSRect clickRect = [[clickStrip valueForKey:@"newTabRect"] rectValue];
		NSPoint clickPoint = NSMakePoint(NSMidX(clickRect), NSMidY(clickRect));
		NSEvent *mouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:clickPoint
			modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1.0];
		NSEvent *mouseUp = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:clickPoint
			modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:2 clickCount:1 pressure:0.0];
		[clickStrip mouseDown:mouseDown];
		[clickStrip mouseUp:mouseUp];
		require(delegate.newTabRequestCount == 1, "clicking the trailing plus should request exactly one new tab");

		NSString *snapshotPath = NSProcessInfo.processInfo.environment[@"NPP_TAB_SNAPSHOT_PATH"];
		if (snapshotPath.length > 0) {
			[tabBar setFrameSize:NSMakeSize(600, 32)];
			tabBar.selectedIndex = 2;
			[tabBar layoutSubtreeIfNeeded];
			NSBitmapImageRep *bitmap = [tabBar bitmapImageRepForCachingDisplayInRect:tabBar.bounds];
			[tabBar cacheDisplayInRect:tabBar.bounds toBitmapImageRep:bitmap];
			NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
			require([png writeToFile:snapshotPath atomically:YES], "tab bar snapshot should be writable");
		}
		std::puts("NppMacTabBarTests passed");
	}
	return 0;
}
