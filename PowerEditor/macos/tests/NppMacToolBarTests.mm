#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacLocalization.h"
#import "NppMacToolBarView.h"

@interface NppMacToolBarTestTarget : NSObject
@property(nonatomic) NSUInteger newDocumentCount;
@end

@implementation NppMacToolBarTestTarget
- (void)newDocument:(id)sender { (void)sender; self.newDocumentCount++; }
@end

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		NppMacToolBarTestTarget *target = [[NppMacToolBarTestTarget alloc] init];
		NppMacToolBarView *toolBar = [[NppMacToolBarView alloc] initWithFrame:NSMakeRect(0, 0, 980, 38)
			target:target];

		NSArray<NSString *> *actions = @[
			@"newDocument:", @"openDocument:", @"saveDocument:", @"saveAllDocuments:",
			@"closeDocument:", @"closeAllDocuments:", @"printDocument:", @"cut:", @"copy:",
			@"paste:", @"undo:", @"redo:", @"findText:", @"replaceText:", @"zoomIn:",
			@"zoomOut:", @"toggleWordWrap:", @"toggleAllCharacters:", @"toggleIndentGuides:",
			@"startMacroRecording:", @"stopMacroRecording:", @"playbackMacro:", @"runMacroMultipleTimes:"
		];
		for (NSString *actionName in actions) {
			require([toolBar buttonForAction:NSSelectorFromString(actionName)] != nil,
				"the original toolbar action should have a button");
		}

		NSButton *newButton = [toolBar buttonForAction:@selector(newDocument:)];
		[newButton performClick:nil];
		require(target.newDocumentCount == 1, "toolbar buttons should dispatch to the application target");
		require([newButton.toolTip isEqualToString:@"新建"], "toolbar should use the default Chinese localization");

		[toolBar setButtonEnabled:NO forAction:@selector(saveDocument:)];
		require(![toolBar buttonForAction:@selector(saveDocument:)].enabled,
			"toolbar commands should expose disabled state");
		[toolBar setButtonOn:YES forAction:@selector(toggleWordWrap:)];
		require([toolBar buttonForAction:@selector(toggleWordWrap:)].state == NSControlStateValueOn,
			"toggle toolbar commands should expose selected state");
		NSButton *openButton = [toolBar buttonForAction:@selector(openDocument:)];
		NSEvent *hoverEvent = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSZeroPoint
			modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:0 pressure:0];
		CGColorRef normalColor = openButton.layer.backgroundColor;
		[openButton mouseEntered:hoverEvent];
		require(!CGColorEqualToColor(normalColor, openButton.layer.backgroundColor),
			"enabled toolbar buttons should show a hover background");
		[openButton mouseExited:hoverEvent];
		require(CGColorGetAlpha(openButton.layer.backgroundColor) == 0,
			"toolbar hover feedback should clear when the pointer leaves");
		NSButton *saveButton = [toolBar buttonForAction:@selector(saveDocument:)];
		[saveButton mouseEntered:hoverEvent];
		require(CGColorGetAlpha(saveButton.layer.backgroundColor) == 0,
			"disabled toolbar buttons should not show hover feedback");

		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"en"];
		[toolBar reloadLocalization];
		require([newButton.toolTip isEqualToString:@"New"], "toolbar tooltips should update with the UI language");

		std::puts("NppMacToolBarTests passed");
	}
	return 0;
}
