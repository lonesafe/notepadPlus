#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacFindPanelController.h"
#import "NppMacLocalization.h"
#import "Scintilla.h"
#import "ScintillaView.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
		[editor setGeneralProperty:SCI_SETCODEPAGE value:SC_CP_UTF8];
		NppMacFindPanelController *controller =
			[[NppMacFindPanelController alloc] initWithEditor:editor ownerWindow:nil];
		NSTabView *localizedTabView = [controller valueForKey:@"tabView"];
		require([localizedTabView.tabViewItems[0].label isEqualToString:@"查找"],
			"find panel should default to Chinese");
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"en"];
		[controller reloadLocalization];
		require([localizedTabView.tabViewItems[0].label isEqualToString:@"Find"],
			"find panel should update to English without being recreated");
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"zh-Hans"];
		[controller reloadLocalization];

		NSTextField *findField = [controller valueForKey:@"findField"];
		NSTextField *replaceField = [controller valueForKey:@"replaceField"];
		NSButton *wholeWord = [controller valueForKey:@"wholeWordCheckbox"];
		NSButton *inSelection = [controller valueForKey:@"inSelectionCheckbox"];
		NSPopUpButton *searchMode = [controller valueForKey:@"searchModePopup"];
		NSPanel *findPanel = [controller valueForKey:@"panel"];
		NSBox *searchModeBox = [controller valueForKey:@"searchModeBox"];
		NSButton *normalModeRadio = [controller valueForKey:@"normalModeRadio"];
		NSButton *extendedModeRadio = [controller valueForKey:@"extendedModeRadio"];
		NSButton *closeButton = [controller valueForKey:@"closeButton"];
		NSScrollView *resultsScrollView = [controller valueForKey:@"resultsScrollView"];
		require(NSHeight(findPanel.contentView.bounds) <= 390, "find panel should use the original compact height");
		require(searchModeBox.superview != nil && normalModeRadio.superview != nil,
			"search modes should be visible as an original-style radio-button group");
		require(closeButton.superview != nil, "the original-style action column should include a close button");
		require(resultsScrollView.superview == nil,
			"find results should not permanently occupy space in the compact find panel");
		[extendedModeRadio performClick:nil];
		require(searchMode.indexOfSelectedItem == 1, "search mode radio buttons should update search behavior");
		[normalModeRadio performClick:nil];

		[editor setString:@"alpha beta alpha\nALPHA"];
		findField.stringValue = @"alpha";
		replaceField.stringValue = @"omega";
		[controller findNext];
		require([editor.selectedString isEqualToString:@"alpha"], "find next should select the first match");

		[controller replaceCurrent];
		require([[editor string] isEqualToString:@"omega beta alpha\nALPHA"], "replace should change the selected match");
		require([editor.selectedString isEqualToString:@"alpha"], "replace should select the next match");

		[controller replaceAll];
		require([[editor string] isEqualToString:@"omega beta omega\nomega"], "replace all should default to case-insensitive matching");

		[editor setString:@"cat scatter cat"];
		findField.stringValue = @"cat";
		replaceField.stringValue = @"dog";
		wholeWord.state = NSControlStateValueOn;
		[controller replaceAll];
		require([[editor string] isEqualToString:@"dog scatter dog"], "whole-word replace should not replace inside another word");

		[editor setString:@"one two one"];
		findField.stringValue = @"one";
		wholeWord.state = NSControlStateValueOff;
		sptr_t length = [editor message:SCI_GETLENGTH];
		[editor message:SCI_SETSEL wParam:(uptr_t)length lParam:length];
		[controller findPrevious];
		require([editor.selectedString isEqualToString:@"one"], "find previous should search backwards");

		[editor setString:@"first\nsecond\nthird"];
		findField.stringValue = @"\\n";
		[searchMode selectItemAtIndex:1];
		[controller performSelector:@selector(searchModeChanged:) withObject:nil];
		[editor message:SCI_SETSEL wParam:0 lParam:0];
		[controller findNext];
		require([editor.selectedString isEqualToString:@"\n"], "extended mode should decode escaped newlines");

		[editor setString:@"alpha12 beta34"];
		findField.stringValue = @"([a-z]+)([0-9]+)";
		replaceField.stringValue = @"$2-$1";
		[searchMode selectItemAtIndex:2];
		[controller performSelector:@selector(searchModeChanged:) withObject:nil];
		[controller replaceAll];
		require([[editor string] isEqualToString:@"12-alpha 34-beta"], "regular-expression replacement should expand capture groups");

		[editor setString:@"red blue red green red"];
		findField.stringValue = @"red";
		[searchMode selectItemAtIndex:0];
		[controller performSelector:@selector(searchModeChanged:) withObject:nil];
		require([controller countAll] == 3, "count should report every match in the current document");
		require([controller markAll] == 3, "mark all should highlight every match");
		require([editor message:SCI_INDICATORVALUEAT wParam:INDICATOR_CONTAINER lParam:0] != 0,
			"marked text should use the search indicator");
		[controller clearAllMarks];
		require([editor message:SCI_INDICATORVALUEAT wParam:INDICATOR_CONTAINER lParam:0] == 0,
			"clear marks should remove search indicators");

		[editor setString:@"cat cat cat"];
		[editor message:SCI_SETSEL wParam:0 lParam:7];
		[controller performSelector:@selector(captureSelectionScope)];
		inSelection.state = NSControlStateValueOn;
		findField.stringValue = @"cat";
		replaceField.stringValue = @"dog";
		[controller replaceAll];
		require([[editor string] isEqualToString:@"dog dog cat"], "replace all in selection should not modify text outside the captured selection");
		inSelection.state = NSControlStateValueOff;

		NppMacFindDocumentSnapshot *first = [[NppMacFindDocumentSnapshot alloc] init];
		first.documentIndex = 0;
		first.displayName = @"first.txt";
		first.text = @"needle one";
		NppMacFindDocumentSnapshot *second = [[NppMacFindDocumentSnapshot alloc] init];
		second.documentIndex = 1;
		second.displayName = @"second.txt";
		second.text = @"two needle needle";
		controller.openDocumentsProvider = ^{ return @[first, second]; };
		findField.stringValue = @"needle";
		replaceField.stringValue = @"found";
		__block NSInteger openDocumentReplacements = 0;
		controller.replaceOpenDocumentHandler = ^(NSUInteger index, NSString *text) {
			(void)index;
			require([text rangeOfString:@"needle"].location == NSNotFound,
				"opened-document replacement should provide fully replaced text");
			openDocumentReplacements++;
		};
		[controller performSelector:@selector(replaceAllOpenedAction:) withObject:nil];
		require(openDocumentReplacements == 2, "replace in opened documents should update every matching buffer");

		NSString *identifier = NSUUID.UUID.UUIDString;
		NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:identifier] isDirectory:YES];
		[[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
		[@"find-me\n" writeToURL:[directory URLByAppendingPathComponent:@"source.cpp"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[@"find-me\n" writeToURL:[directory URLByAppendingPathComponent:@"ignored.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
		NSTextField *directoryField = [controller valueForKey:@"directoryField"];
		NSTextField *filtersField = [controller valueForKey:@"filtersField"];
		directoryField.stringValue = directory.path;
		filtersField.stringValue = @"*.cpp";
		findField.stringValue = @"find-me";
		[controller performSelector:@selector(findInFilesAction:) withObject:nil];
		NSTextView *resultsView = [controller valueForKey:@"resultsView"];
		require([resultsView.string containsString:@"source.cpp"] && ![resultsView.string containsString:@"ignored.txt"],
			"find in files should honor wildcard filters");
		[[NSFileManager defaultManager] removeItemAtURL:directory error:nil];

		NSString *snapshotDirectory = NSProcessInfo.processInfo.environment[@"NPP_FIND_SNAPSHOT_DIR"];
		if (snapshotDirectory.length > 0) {
			findPanel.contentView.wantsLayer = YES;
			findPanel.contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
			NSTabView *tabView = [controller valueForKey:@"tabView"];
			NSArray<NSString *> *names = @[@"find", @"replace", @"files", @"mark"];
			for (NSUInteger index = 0; index < names.count; ++index) {
				[tabView selectTabViewItemAtIndex:index];
				[findPanel.contentView layoutSubtreeIfNeeded];
				NSBitmapImageRep *bitmap = [findPanel.contentView bitmapImageRepForCachingDisplayInRect:findPanel.contentView.bounds];
				[findPanel.contentView cacheDisplayInRect:findPanel.contentView.bounds toBitmapImageRep:bitmap];
				NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
				NSString *path = [snapshotDirectory stringByAppendingPathComponent:
					[NSString stringWithFormat:@"find-panel-%@.png", names[index]]];
				require([png writeToFile:path atomically:YES], "find panel snapshot should be writable");
			}
		}

		std::puts("NppMacFindPanelTests passed");
	}
	return 0;
}
