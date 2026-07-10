#import "NppMacFindPanelController.h"
#import "NppMacLocalization.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

#import "BoostRegexSearch.h"
#import "Scintilla.h"
#import "ScintillaView.h"

static const NSInteger kFindIndicator = INDICATOR_CONTAINER;
static const NSInteger kFindBookmarkMarker = 24;

typedef NS_ENUM(NSInteger, NppMacFindTab) {
	NppMacFindTabFind = 0,
	NppMacFindTabReplace,
	NppMacFindTabFiles,
	NppMacFindTabMark
};

typedef NS_ENUM(NSInteger, NppMacSearchMode) {
	NppMacSearchModeNormal = 0,
	NppMacSearchModeExtended,
	NppMacSearchModeRegex
};

@implementation NppMacFindDocumentSnapshot
@end

@interface NppMacFindPanelController () <NSTabViewDelegate, NSWindowDelegate>
@property(nonatomic, weak) ScintillaView *editor;
@property(nonatomic, weak) NSWindow *ownerWindow;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSTabView *tabView;
@property(nonatomic, strong) NSTextField *findField;
@property(nonatomic, strong) NSTextField *replaceField;
@property(nonatomic, strong) NSTextField *filtersField;
@property(nonatomic, strong) NSTextField *directoryField;
@property(nonatomic, strong) NSButton *matchCaseCheckbox;
@property(nonatomic, strong) NSButton *wholeWordCheckbox;
@property(nonatomic, strong) NSButton *wrapCheckbox;
@property(nonatomic, strong) NSButton *backwardsCheckbox;
@property(nonatomic, strong) NSButton *inSelectionCheckbox;
@property(nonatomic, strong) NSButton *dotMatchesNewlineCheckbox;
@property(nonatomic, strong) NSButton *recursiveCheckbox;
@property(nonatomic, strong) NSButton *hiddenFoldersCheckbox;
@property(nonatomic, strong) NSButton *bookmarkLineCheckbox;
@property(nonatomic, strong) NSButton *purgeCheckbox;
@property(nonatomic, strong) NSPopUpButton *searchModePopup;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextView *resultsView;
@property(nonatomic, strong) NSScrollView *resultsScrollView;
@property(nonatomic, strong) NSTextField *findLabel;
@property(nonatomic, strong) NSTextField *secondaryLabel;
@property(nonatomic, strong) NSTextField *directoryLabel;
@property(nonatomic, strong) NSTextField *searchModeLabel;
@property(nonatomic, strong) NSMutableArray<NSView *> *sharedControls;
@property(nonatomic, strong) NSArray<NSValue *> *markedRanges;
@property(nonatomic) sptr_t selectionScopeStart;
@property(nonatomic) sptr_t selectionScopeEnd;
@end

@implementation NppMacFindPanelController

- (instancetype)initWithEditor:(ScintillaView *)editor ownerWindow:(NSWindow *)ownerWindow {
	self = [super init];
	if (self) {
		_editor = editor;
		_ownerWindow = ownerWindow;
		_selectionScopeStart = -1;
		_selectionScopeEnd = -1;
		_markedRanges = @[];
		[self buildPanel];
		[self configureIndicator];
	}
	return self;
}

- (void)buildPanel {
	NSRect frame = NSMakeRect(0, 0, 680, 510);
	NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
		NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
	self.panel = [[NSPanel alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
	self.panel.title = @"Find";
	self.panel.floatingPanel = YES;
	self.panel.hidesOnDeactivate = NO;
	self.panel.releasedWhenClosed = NO;
	self.panel.minSize = NSMakeSize(680, 510);
	self.panel.delegate = self;

	self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(12, 38, 656, 460)];
	self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	self.tabView.delegate = self;
	for (NSString *title in @[@"Find", @"Replace", @"Find in Files", @"Mark"]) {
		NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:title];
		item.label = title;
		item.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 420)];
		[self.tabView addTabViewItem:item];
	}
	[self.panel.contentView addSubview:self.tabView];

	self.findField = [self textFieldWithPlaceholder:@"Text to find"];
	self.findField.target = self;
	self.findField.action = @selector(findNextAction:);
	self.replaceField = [self textFieldWithPlaceholder:@"Replacement text"];
	self.filtersField = [self textFieldWithPlaceholder:@"*.cpp *.h;*.txt"];
	self.filtersField.stringValue = @"*";
	self.directoryField = [self textFieldWithPlaceholder:@"Directory"];
	self.findLabel = [self label:@"Find what:"];
	self.secondaryLabel = [self label:@""];
	self.directoryLabel = [self label:@"Directory:"];
	self.searchModeLabel = [self label:@"Search mode:"];

	self.matchCaseCheckbox = [self checkbox:@"Match case" action:nil];
	self.wholeWordCheckbox = [self checkbox:@"Match whole word only" action:nil];
	self.wrapCheckbox = [self checkbox:@"Wrap around" action:nil];
	self.wrapCheckbox.state = NSControlStateValueOn;
	self.backwardsCheckbox = [self checkbox:@"Backward direction" action:nil];
	self.inSelectionCheckbox = [self checkbox:@"In selection" action:@selector(selectionScopeChanged:)];
	self.dotMatchesNewlineCheckbox = [self checkbox:@". matches newline" action:nil];
	self.recursiveCheckbox = [self checkbox:@"In all sub-folders" action:nil];
	self.recursiveCheckbox.state = NSControlStateValueOn;
	self.hiddenFoldersCheckbox = [self checkbox:@"In hidden folders" action:nil];
	self.bookmarkLineCheckbox = [self checkbox:@"Bookmark line" action:nil];
	self.purgeCheckbox = [self checkbox:@"Purge for each search" action:nil];
	self.purgeCheckbox.state = NSControlStateValueOn;

	self.searchModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[self.searchModePopup addItemsWithTitles:@[@"Normal", @"Extended (\\n, \\r, \\t, \\0, \\x...)", @"Regular expression"]];
	self.searchModePopup.target = self;
	self.searchModePopup.action = @selector(searchModeChanged:);

	self.resultsView = [[NSTextView alloc] initWithFrame:NSZeroRect];
	self.resultsView.editable = NO;
	self.resultsView.selectable = YES;
	self.resultsView.font = [NSFont fontWithName:@"Menlo" size:11.0] ?: [NSFont systemFontOfSize:11.0];
	self.resultsView.verticallyResizable = YES;
	self.resultsView.horizontallyResizable = NO;
	self.resultsView.textContainer.widthTracksTextView = YES;
	self.resultsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	self.resultsScrollView.borderType = NSBezelBorder;
	self.resultsScrollView.hasVerticalScroller = YES;
	self.resultsScrollView.documentView = self.resultsView;

	self.statusLabel = [self label:@""];
	self.statusLabel.textColor = NSColor.secondaryLabelColor;
	self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	self.statusLabel.frame = NSMakeRect(20, 10, 640, 22);
	self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
	[self.panel.contentView addSubview:self.statusLabel];

	self.sharedControls = [NSMutableArray arrayWithArray:@[
		self.findLabel, self.secondaryLabel, self.directoryLabel, self.searchModeLabel,
		self.findField, self.replaceField, self.filtersField, self.directoryField,
		self.matchCaseCheckbox, self.wholeWordCheckbox, self.wrapCheckbox, self.backwardsCheckbox,
		self.inSelectionCheckbox, self.dotMatchesNewlineCheckbox, self.recursiveCheckbox,
		self.hiddenFoldersCheckbox, self.bookmarkLineCheckbox, self.purgeCheckbox,
		self.searchModePopup, self.resultsScrollView
	]];

	NSArray<NSDictionary *> *buttons = @[
		@{@"title": @"Find Next", @"action": NSStringFromSelector(@selector(findNextAction:)), @"tag": @100},
		@{@"title": @"Find Previous", @"action": NSStringFromSelector(@selector(findPreviousAction:)), @"tag": @101},
		@{@"title": @"Count", @"action": NSStringFromSelector(@selector(countAction:)), @"tag": @102},
		@{@"title": @"Find All in Current\nDocument", @"action": NSStringFromSelector(@selector(findAllCurrentAction:)), @"tag": @103},
		@{@"title": @"Find All in All Opened\nDocuments", @"action": NSStringFromSelector(@selector(findAllOpenedAction:)), @"tag": @104},
		@{@"title": @"Replace", @"action": NSStringFromSelector(@selector(replaceCurrentAction:)), @"tag": @200},
		@{@"title": @"Replace All", @"action": NSStringFromSelector(@selector(replaceAllAction:)), @"tag": @201},
		@{@"title": @"Replace All in All Opened\nDocuments", @"action": NSStringFromSelector(@selector(replaceAllOpenedAction:)), @"tag": @202},
		@{@"title": @"Find All", @"action": NSStringFromSelector(@selector(findInFilesAction:)), @"tag": @300},
		@{@"title": @"Replace in Files", @"action": NSStringFromSelector(@selector(replaceInFilesAction:)), @"tag": @301},
		@{@"title": @"Browse...", @"action": NSStringFromSelector(@selector(browseDirectoryAction:)), @"tag": @302},
		@{@"title": @"Mark All", @"action": NSStringFromSelector(@selector(markAllAction:)), @"tag": @400},
		@{@"title": @"Clear all marks", @"action": NSStringFromSelector(@selector(clearMarksAction:)), @"tag": @401},
		@{@"title": @"Copy Marked Text", @"action": NSStringFromSelector(@selector(copyMarkedTextAction:)), @"tag": @402}
	];
	for (NSDictionary *spec in buttons) {
		NSButton *button = [self button:spec[@"title"] action:NSSelectorFromString(spec[@"action"])];
		button.tag = [spec[@"tag"] integerValue];
		[self.sharedControls addObject:button];
	}

	[self.tabView selectTabViewItemAtIndex:NppMacFindTabFind];
	[self reloadLocalization];
	[self layoutControlsForTab:NppMacFindTabFind];
}

- (void)reloadLocalization {
	if (!self.panel) {
		return;
	}
	NSArray<NSString *> *tabKeys = @[@"find.tab.find", @"find.tab.replace", @"find.tab.files", @"find.tab.mark"];
	for (NSUInteger index = 0; index < tabKeys.count; ++index) {
		[self.tabView tabViewItemAtIndex:index].label = NppLocalizedString(tabKeys[index]);
	}
	self.findField.placeholderString = NppL("find.placeholder.search");
	self.replaceField.placeholderString = NppL("find.placeholder.replace");
	self.directoryField.placeholderString = NppL("find.placeholder.directory");
	self.findLabel.stringValue = NppL("find.findWhat");
	self.directoryLabel.stringValue = NppL("find.directory");
	self.searchModeLabel.stringValue = NppL("find.searchMode");
	self.matchCaseCheckbox.title = NppL("find.option.matchCase");
	self.wholeWordCheckbox.title = NppL("find.option.wholeWord");
	self.wrapCheckbox.title = NppL("find.option.wrap");
	self.backwardsCheckbox.title = NppL("find.option.backward");
	self.inSelectionCheckbox.title = NppL("find.option.selection");
	self.dotMatchesNewlineCheckbox.title = NppL("find.option.dotNewline");
	self.recursiveCheckbox.title = NppL("find.option.recursive");
	self.hiddenFoldersCheckbox.title = NppL("find.option.hidden");
	self.bookmarkLineCheckbox.title = NppL("find.option.bookmark");
	self.purgeCheckbox.title = NppL("find.option.purge");
	NSInteger mode = self.searchModePopup.indexOfSelectedItem;
	[self.searchModePopup removeAllItems];
	[self.searchModePopup addItemsWithTitles:@[NppL("find.mode.normal"), NppL("find.mode.extended"), NppL("find.mode.regex")]];
	[self.searchModePopup selectItemAtIndex:MAX(mode, 0)];
	NSDictionary<NSNumber *, NSString *> *buttonKeys = @{
		@100: @"find.action.next", @101: @"find.action.previous", @102: @"find.action.count",
		@103: @"find.action.allCurrent", @104: @"find.action.allOpened", @200: @"find.action.replace",
		@201: @"find.action.replaceAll", @202: @"find.action.replaceOpened", @300: @"find.action.findAll",
		@301: @"find.action.replaceFiles", @302: @"find.action.browse", @400: @"find.action.markAll",
		@401: @"find.action.clearMarks", @402: @"find.action.copyMarked"
	};
	for (NSView *view in self.sharedControls) {
		if ([view isKindOfClass:NSButton.class] && buttonKeys[@(((NSButton *)view).tag)]) {
			((NSButton *)view).title = NppLocalizedString(buttonKeys[@(((NSButton *)view).tag)]);
		}
	}
	NppMacFindTab tab = (NppMacFindTab)[self.tabView indexOfTabViewItem:self.tabView.selectedTabViewItem];
	[self layoutControlsForTab:tab];
}

- (NSTextField *)textFieldWithPlaceholder:(NSString *)placeholder {
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	field.placeholderString = placeholder;
	return field;
}

- (NSTextField *)label:(NSString *)title {
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	label.stringValue = title;
	label.bezeled = NO;
	label.drawsBackground = NO;
	label.editable = NO;
	label.selectable = NO;
	return label;
}

- (NSButton *)checkbox:(NSString *)title action:(SEL)action {
	NSButton *button = [NSButton checkboxWithTitle:title target:self action:action];
	return button;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
	NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
	button.title = title;
	button.bezelStyle = NSBezelStyleRounded;
	button.target = self;
	button.action = action;
	button.cell.wraps = YES;
	button.cell.usesSingleLineMode = NO;
	button.cell.lineBreakMode = NSLineBreakByWordWrapping;
	return button;
}

- (void)windowDidResize:(NSNotification *)notification {
	if (notification.object == self.panel && self.tabView.selectedTabViewItem) {
		[self layoutControlsForTab:(NppMacFindTab)[self.tabView indexOfTabViewItem:self.tabView.selectedTabViewItem]];
	}
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	(void)tabViewItem;
	[self layoutControlsForTab:(NppMacFindTab)[tabView indexOfTabViewItem:tabView.selectedTabViewItem]];
}

- (void)layoutControlsForTab:(NppMacFindTab)tab {
	if (tab < 0 || tab >= (NSInteger)self.tabView.numberOfTabViewItems) {
		return;
	}
	NSView *content = [self.tabView tabViewItemAtIndex:tab].view;
	for (NSView *view in self.sharedControls) {
		[content addSubview:view];
		view.hidden = NO;
	}

	CGFloat width = NSWidth(content.bounds);
	CGFloat actionWidth = 170.0;
	CGFloat actionX = width - actionWidth - 8.0;
	self.findField.frame = NSMakeRect(104, 355, actionX - 120, 26);
	self.findLabel.frame = NSMakeRect(18, 358, 80, 22);
	self.replaceField.frame = NSMakeRect(104, 317, actionX - 120, 26);
	self.filtersField.frame = NSMakeRect(104, 317, actionX - 120, 26);
	self.directoryField.frame = NSMakeRect(104, 279, actionX - 120, 26);
	self.secondaryLabel.frame = NSMakeRect(18, 320, 80, 22);
	self.directoryLabel.frame = NSMakeRect(18, 282, 80, 22);
	self.matchCaseCheckbox.frame = NSMakeRect(18, 222, 190, 24);
	self.wholeWordCheckbox.frame = NSMakeRect(18, 246, 190, 24);
	self.wrapCheckbox.frame = NSMakeRect(220, 246, 150, 24);
	self.backwardsCheckbox.frame = NSMakeRect(220, 222, 190, 24);
	self.inSelectionCheckbox.frame = NSMakeRect(220, 198, 150, 24);
	self.dotMatchesNewlineCheckbox.frame = NSMakeRect(18, 198, 180, 24);
	self.searchModeLabel.frame = NSMakeRect(18, 168, 88, 22);
	self.searchModePopup.frame = NSMakeRect(110, 164, 340, 28);
	self.recursiveCheckbox.frame = NSMakeRect(18, 246, 180, 24);
	self.hiddenFoldersCheckbox.frame = NSMakeRect(220, 246, 170, 24);
	self.bookmarkLineCheckbox.frame = NSMakeRect(18, 280, 160, 24);
	self.purgeCheckbox.frame = NSMakeRect(18, 256, 190, 24);
	self.resultsScrollView.frame = NSMakeRect(18, 12, actionX - 36, 140);
	self.resultsScrollView.autoresizingMask = NSViewWidthSizable;

	self.replaceField.hidden = tab != NppMacFindTabReplace;
	self.filtersField.hidden = tab != NppMacFindTabFiles;
	self.directoryField.hidden = tab != NppMacFindTabFiles;
	self.recursiveCheckbox.hidden = tab != NppMacFindTabFiles;
	self.hiddenFoldersCheckbox.hidden = tab != NppMacFindTabFiles;
	self.bookmarkLineCheckbox.hidden = tab != NppMacFindTabMark;
	self.purgeCheckbox.hidden = tab != NppMacFindTabMark;
	self.secondaryLabel.hidden = tab == NppMacFindTabFind || tab == NppMacFindTabMark;
	self.directoryLabel.hidden = tab != NppMacFindTabFiles;
	if (tab == NppMacFindTabFiles) {
		self.matchCaseCheckbox.frame = NSMakeRect(220, 222, 190, 24);
		self.wholeWordCheckbox.frame = NSMakeRect(18, 222, 190, 24);
		self.dotMatchesNewlineCheckbox.frame = NSMakeRect(220, 198, 180, 24);
	} else if (tab == NppMacFindTabMark) {
		self.matchCaseCheckbox.frame = NSMakeRect(18, 198, 190, 24);
		self.wholeWordCheckbox.frame = NSMakeRect(18, 222, 190, 24);
		self.inSelectionCheckbox.frame = NSMakeRect(220, 222, 150, 24);
		self.dotMatchesNewlineCheckbox.frame = NSMakeRect(220, 198, 180, 24);
	}
	self.secondaryLabel.stringValue = tab == NppMacFindTabReplace ? NppL("find.replaceWith") : NppL("find.filters");
	if (tab == NppMacFindTabFiles) {
		NSTextField *directoryLabel = self.secondaryLabel;
		directoryLabel.stringValue = NppL("find.filters");
	}
	self.wrapCheckbox.hidden = tab == NppMacFindTabFiles || tab == NppMacFindTabMark;
	self.backwardsCheckbox.hidden = tab != NppMacFindTabFind;
	self.inSelectionCheckbox.hidden = tab == NppMacFindTabFiles;

	for (NSView *view in self.sharedControls) {
		if (![view isKindOfClass:NSButton.class] || ((NSButton *)view).tag < 100) {
			continue;
		}
		NSButton *button = (NSButton *)view;
		NSInteger group = button.tag / 100;
		button.hidden = group != tab + 1;
		NSInteger row = button.tag % 100;
		BOOL longTitle = button.title.length > 18 || [button.title rangeOfString:@"\n"].location != NSNotFound;
		button.frame = NSMakeRect(actionX, 354 - row * 46, actionWidth, longTitle ? 42 : 30);
		if (button.tag == 302) {
			button.frame = NSMakeRect(actionX, 278, actionWidth, 30);
		}
	}

	self.panel.title = @[NppL("find.tab.find"), NppL("find.tab.replace"), NppL("find.tab.files"), NppL("find.tab.mark")][(NSUInteger)tab];
	[self searchModeChanged:nil];
}

- (void)showFindPanel { [self showTab:NppMacFindTabFind focus:self.findField]; }
- (void)showReplacePanel { [self showTab:NppMacFindTabReplace focus:self.replaceField]; }
- (void)showFindInFilesPanel { [self showTab:NppMacFindTabFiles focus:self.findField]; }
- (void)showMarkPanel { [self showTab:NppMacFindTabMark focus:self.findField]; }

- (void)showTab:(NppMacFindTab)tab focus:(NSView *)field {
	NSString *selection = self.editor.selectedString;
	if (selection.length > 0 && [selection rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location == NSNotFound) {
		self.findField.stringValue = selection;
	}
	[self captureSelectionScope];
	self.statusLabel.stringValue = @"";
	[self.tabView selectTabViewItemAtIndex:tab];
	if (!self.panel.isVisible) {
		[self.panel center];
	}
	[self.panel makeKeyAndOrderFront:nil];
	[self.panel makeFirstResponder:field];
	if (field == self.findField) {
		[(NSTextField *)field selectText:nil];
	}
}

- (void)captureSelectionScope {
	self.selectionScopeStart = [self.editor message:SCI_GETSELECTIONSTART];
	self.selectionScopeEnd = [self.editor message:SCI_GETSELECTIONEND];
	BOOL hasSelection = self.selectionScopeEnd > self.selectionScopeStart;
	self.inSelectionCheckbox.enabled = hasSelection;
	if (!hasSelection) {
		self.inSelectionCheckbox.state = NSControlStateValueOff;
	}
}

- (void)selectionScopeChanged:(id)sender {
	(void)sender;
	if (self.inSelectionCheckbox.state == NSControlStateValueOn) {
		[self captureSelectionScope];
		self.inSelectionCheckbox.state = self.selectionScopeEnd > self.selectionScopeStart
			? NSControlStateValueOn : NSControlStateValueOff;
	}
}

- (NppMacSearchMode)searchMode {
	return (NppMacSearchMode)self.searchModePopup.indexOfSelectedItem;
}

- (void)searchModeChanged:(id)sender {
	(void)sender;
	BOOL regex = self.searchMode == NppMacSearchModeRegex;
	self.dotMatchesNewlineCheckbox.enabled = regex;
	if (!regex) {
		self.dotMatchesNewlineCheckbox.state = NSControlStateValueOff;
	}
	self.wholeWordCheckbox.enabled = !regex;
}

- (NSString *)decodedExtendedText:(NSString *)text {
	NSMutableString *result = [NSMutableString string];
	for (NSUInteger index = 0; index < text.length; ++index) {
		unichar ch = [text characterAtIndex:index];
		if (ch != '\\' || index + 1 >= text.length) {
			[result appendFormat:@"%C", ch];
			continue;
		}
		unichar escaped = [text characterAtIndex:++index];
		switch (escaped) {
			case 'n': [result appendString:@"\n"]; break;
			case 'r': [result appendString:@"\r"]; break;
			case 't': [result appendString:@"\t"]; break;
			case '0': [result appendString:[NSString stringWithCharacters:(unichar[]){0} length:1]]; break;
			case '\\': [result appendString:@"\\"]; break;
			case 'x': {
				NSUInteger start = index + 1;
				NSUInteger end = start;
				while (end < text.length && end - start < 4 &&
					[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] characterIsMember:[text characterAtIndex:end]]) {
					end++;
				}
				if (end == start) {
					[result appendString:@"x"];
				} else {
					unsigned value = 0;
					[[NSScanner scannerWithString:[text substringWithRange:NSMakeRange(start, end - start)]] scanHexInt:&value];
					[result appendFormat:@"%C", (unichar)value];
					index = end - 1;
				}
				break;
			}
			default: [result appendFormat:@"%C", escaped]; break;
		}
	}
	return result;
}

- (NSString *)searchText {
	return self.searchMode == NppMacSearchModeExtended
		? [self decodedExtendedText:self.findField.stringValue] : self.findField.stringValue;
}

- (NSString *)replacementText {
	return self.searchMode == NppMacSearchModeExtended
		? [self decodedExtendedText:self.replaceField.stringValue] : self.replaceField.stringValue;
}

- (NSString *)scintillaRegexReplacementText {
	NSString *replacement = [self replacementText];
	NSMutableString *result = [NSMutableString string];
	for (NSUInteger index = 0; index < replacement.length; ++index) {
		unichar ch = [replacement characterAtIndex:index];
		if (ch == '$' && index + 1 < replacement.length &&
			[[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[replacement characterAtIndex:index + 1]]) {
			[result appendString:@"\\"];
		} else {
			[result appendFormat:@"%C", ch];
		}
	}
	return result;
}

- (NSString *)foundationRegexReplacementText {
	NSString *replacement = [self replacementText];
	NSMutableString *result = [NSMutableString string];
	for (NSUInteger index = 0; index < replacement.length; ++index) {
		unichar ch = [replacement characterAtIndex:index];
		if (ch == '\\' && index + 1 < replacement.length &&
			[[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[replacement characterAtIndex:index + 1]]) {
			[result appendString:@"$"];
		} else {
			[result appendFormat:@"%C", ch];
		}
	}
	return result;
}

- (uptr_t)searchFlags {
	uptr_t flags = SCFIND_NONE;
	if (self.matchCaseCheckbox.state == NSControlStateValueOn) flags |= SCFIND_MATCHCASE;
	if (self.wholeWordCheckbox.state == NSControlStateValueOn && self.searchMode != NppMacSearchModeRegex) flags |= SCFIND_WHOLEWORD;
	if (self.searchMode == NppMacSearchModeRegex) {
		flags |= SCFIND_REGEXP | SCFIND_CXX11REGEX;
		if (self.dotMatchesNewlineCheckbox.state == NSControlStateValueOn) flags |= SCFIND_REGEXP_DOTMATCHESNL;
	}
	return flags;
}

- (void)scopeStart:(sptr_t *)start end:(sptr_t *)end {
	*start = 0;
	*end = [self.editor message:SCI_GETLENGTH];
	if (self.inSelectionCheckbox.state == NSControlStateValueOn && self.selectionScopeEnd > self.selectionScopeStart) {
		*start = self.selectionScopeStart;
		*end = self.selectionScopeEnd;
	}
}

- (sptr_t)searchFrom:(sptr_t)start to:(sptr_t)end pattern:(NSString *)pattern {
	NSData *data = [pattern dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
	[self.editor message:SCI_SETSEARCHFLAGS wParam:[self searchFlags]];
	[self.editor message:SCI_SETTARGETSTART wParam:(uptr_t)start];
	[self.editor message:SCI_SETTARGETEND wParam:(uptr_t)end];
	return [ScintillaView directCall:self.editor message:SCI_SEARCHINTARGET
		wParam:data.length lParam:reinterpret_cast<sptr_t>(data.bytes)];
}

- (void)findNext { [self findBackwards:self.backwardsCheckbox.state == NSControlStateValueOn]; }
- (void)findPrevious { [self findBackwards:YES]; }

- (void)findBackwards:(BOOL)backwards {
	NSString *pattern = [self searchText];
	if (pattern.length == 0) {
		[self showFindPanel];
		self.statusLabel.stringValue = NppL("find.status.enter");
		return;
	}
	sptr_t scopeStart = 0, scopeEnd = 0;
	[self scopeStart:&scopeStart end:&scopeEnd];
	sptr_t selectionStart = [self.editor message:SCI_GETSELECTIONSTART];
	sptr_t selectionEnd = [self.editor message:SCI_GETSELECTIONEND];
	sptr_t firstStart = backwards ? MIN(selectionStart, scopeEnd) : MAX(selectionEnd, scopeStart);
	sptr_t result = [self searchFrom:firstStart to:backwards ? scopeStart : scopeEnd pattern:pattern];
	BOOL wrapped = NO;
	if (result < 0 && self.wrapCheckbox.state == NSControlStateValueOn) {
		wrapped = YES;
		result = [self searchFrom:backwards ? scopeEnd : scopeStart to:firstStart pattern:pattern];
	}
	if (result < 0) {
		self.statusLabel.stringValue = NppL("find.status.none");
		NSBeep();
		return;
	}
	sptr_t targetStart = [self.editor message:SCI_GETTARGETSTART];
	sptr_t targetEnd = [self.editor message:SCI_GETTARGETEND];
	[self.editor message:SCI_SETSEL wParam:(uptr_t)targetStart lParam:targetEnd];
	[self.editor message:SCI_SCROLLCARET];
	self.statusLabel.stringValue = wrapped ? NppL("find.status.wrapped") : NppL("find.status.found");
}

- (BOOL)selectionMatchesSearchText:(NSString *)pattern {
	sptr_t start = [self.editor message:SCI_GETSELECTIONSTART];
	sptr_t end = [self.editor message:SCI_GETSELECTIONEND];
	if (start == end) return NO;
	sptr_t result = [self searchFrom:start to:end pattern:pattern];
	return result == start && [self.editor message:SCI_GETTARGETEND] == end;
}

- (sptr_t)replaceTargetWithText:(NSString *)replacement regex:(BOOL)regex {
	NSData *data = [replacement dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
	return [ScintillaView directCall:self.editor message:regex ? SCI_REPLACETARGETRE : SCI_REPLACETARGET
		wParam:data.length lParam:reinterpret_cast<sptr_t>(data.bytes)];
}

- (void)replaceCurrent {
	NSString *pattern = [self searchText];
	if (pattern.length == 0) {
		[self showReplacePanel];
		self.statusLabel.stringValue = NppL("find.status.enter");
		return;
	}
	if (![self selectionMatchesSearchText:pattern]) {
		[self findNext];
		return;
	}
	sptr_t start = [self.editor message:SCI_GETSELECTIONSTART];
	sptr_t end = [self.editor message:SCI_GETSELECTIONEND];
	[self.editor message:SCI_SETTARGETSTART wParam:(uptr_t)start];
	[self.editor message:SCI_SETTARGETEND wParam:(uptr_t)end];
	BOOL regex = self.searchMode == NppMacSearchModeRegex;
	sptr_t length = [self replaceTargetWithText:regex ? [self scintillaRegexReplacementText] : [self replacementText]
		regex:regex];
	[self.editor message:SCI_SETSEL wParam:(uptr_t)start lParam:start + length];
	[self findNext];
}

- (void)replaceAll {
	NSString *pattern = [self searchText];
	if (pattern.length == 0) {
		[self showReplacePanel];
		self.statusLabel.stringValue = NppL("find.status.enter");
		return;
	}
	sptr_t start = 0, end = 0;
	[self scopeStart:&start end:&end];
	sptr_t position = start;
	NSInteger count = 0;
	[self.editor message:SCI_BEGINUNDOACTION];
	while (position <= end) {
		sptr_t found = [self searchFrom:position to:end pattern:pattern];
		if (found < 0) break;
		sptr_t matchStart = [self.editor message:SCI_GETTARGETSTART];
		sptr_t matchEnd = [self.editor message:SCI_GETTARGETEND];
		BOOL regex = self.searchMode == NppMacSearchModeRegex;
		sptr_t replacementLength = [self replaceTargetWithText:regex ? [self scintillaRegexReplacementText] : [self replacementText]
			regex:regex];
		end += replacementLength - (matchEnd - matchStart);
		position = matchStart + replacementLength;
		if (matchStart == matchEnd && replacementLength == 0) position++;
		count++;
	}
	[self.editor message:SCI_ENDUNDOACTION];
	if (self.inSelectionCheckbox.state == NSControlStateValueOn) {
		self.selectionScopeEnd = end;
	}
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.replaced"), (long)count];
	if (count == 0) NSBeep();
}

- (NSArray<NSValue *> *)allMatchesInEditor {
	NSString *pattern = [self searchText];
	if (pattern.length == 0) return @[];
	sptr_t start = 0, end = 0;
	[self scopeStart:&start end:&end];
	NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
	sptr_t position = start;
	while (position <= end) {
		sptr_t found = [self searchFrom:position to:end pattern:pattern];
		if (found < 0) break;
		sptr_t matchStart = [self.editor message:SCI_GETTARGETSTART];
		sptr_t matchEnd = [self.editor message:SCI_GETTARGETEND];
		[ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)matchStart, (NSUInteger)(matchEnd - matchStart))]];
		position = matchEnd > matchStart ? matchEnd : matchStart + 1;
	}
	return ranges;
}

- (NSInteger)countAll {
	NSInteger count = self.allMatchesInEditor.count;
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.count"), (long)count];
	return count;
}

- (void)configureIndicator {
	[self.editor message:SCI_INDICSETSTYLE wParam:kFindIndicator lParam:INDIC_ROUNDBOX];
	[self.editor message:SCI_INDICSETFORE wParam:kFindIndicator lParam:0x4BC3FF];
	[self.editor message:SCI_INDICSETALPHA wParam:kFindIndicator lParam:90];
	[self.editor message:SCI_INDICSETOUTLINEALPHA wParam:kFindIndicator lParam:180];
	[self.editor message:SCI_MARKERDEFINE wParam:kFindBookmarkMarker lParam:SC_MARK_BOOKMARK];
	[self.editor message:SCI_MARKERSETBACK wParam:kFindBookmarkMarker lParam:0x3CAAFA];
}

- (NSInteger)markAll {
	if (self.purgeCheckbox.state == NSControlStateValueOn) [self clearAllMarks];
	NSArray<NSValue *> *ranges = self.allMatchesInEditor;
	[self.editor message:SCI_SETINDICATORCURRENT wParam:kFindIndicator];
	for (NSValue *value in ranges) {
		NSRange range = value.rangeValue;
		[self.editor message:SCI_INDICATORFILLRANGE wParam:range.location lParam:range.length];
		if (self.bookmarkLineCheckbox.state == NSControlStateValueOn) {
			sptr_t line = [self.editor message:SCI_LINEFROMPOSITION wParam:range.location];
			[self.editor message:SCI_MARKERADD wParam:(uptr_t)line lParam:kFindBookmarkMarker];
		}
	}
	self.markedRanges = ranges;
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.marked"), (long)ranges.count];
	return ranges.count;
}

- (void)clearAllMarks {
	sptr_t length = [self.editor message:SCI_GETLENGTH];
	[self.editor message:SCI_SETINDICATORCURRENT wParam:kFindIndicator];
	[self.editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
	[self.editor message:SCI_MARKERDELETEALL wParam:kFindBookmarkMarker];
	self.markedRanges = @[];
	self.statusLabel.stringValue = NppL("find.status.cleared");
}

- (NSString *)textForByteRange:(NSRange)range {
	[self.editor message:SCI_SETTARGETSTART wParam:range.location];
	[self.editor message:SCI_SETTARGETEND wParam:NSMaxRange(range)];
	std::vector<char> buffer(range.length + 1, '\0');
	[ScintillaView directCall:self.editor message:SCI_GETTARGETTEXT wParam:0
		lParam:reinterpret_cast<sptr_t>(buffer.data())];
	return [NSString stringWithUTF8String:buffer.data()] ?: @"";
}

- (void)findAllCurrentAction:(id)sender {
	(void)sender;
	NSArray<NSValue *> *ranges = self.allMatchesInEditor;
	NSMutableString *results = [NSMutableString string];
	for (NSValue *value in ranges) {
		NSRange range = value.rangeValue;
		NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:range.location] + 1;
		[results appendFormat:NppL("find.result.line"), (long)line, [self textForByteRange:range]];
	}
	self.resultsView.string = results;
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.currentResults"), (long)ranges.count];
}

- (NSArray<NSValue *> *)rangesInString:(NSString *)text error:(NSError **)error {
	NSString *pattern = [self searchText];
	if (pattern.length == 0) return @[];
	if (self.searchMode == NppMacSearchModeRegex) {
		NSRegularExpressionOptions options = 0;
		if (self.matchCaseCheckbox.state != NSControlStateValueOn) options |= NSRegularExpressionCaseInsensitive;
		if (self.dotMatchesNewlineCheckbox.state == NSControlStateValueOn) options |= NSRegularExpressionDotMatchesLineSeparators;
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:error];
		return [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)].count > 0
			? [[regex matchesInString:text options:0 range:NSMakeRange(0, text.length)] valueForKey:@"range"] : @[];
	}
	NSStringCompareOptions options = self.matchCaseCheckbox.state == NSControlStateValueOn ? 0 : NSCaseInsensitiveSearch;
	NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
	NSRange remaining = NSMakeRange(0, text.length);
	while (remaining.location < text.length) {
		NSRange found = [text rangeOfString:pattern options:options range:remaining];
		if (found.location == NSNotFound) break;
		BOOL wholeWord = self.wholeWordCheckbox.state == NSControlStateValueOn;
		BOOL valid = !wholeWord || [self rangeIsWholeWord:found inString:text];
		if (valid) [ranges addObject:[NSValue valueWithRange:found]];
		NSUInteger next = NSMaxRange(found);
		if (found.length == 0) next++;
		remaining = next < text.length ? NSMakeRange(next, text.length - next) : NSMakeRange(text.length, 0);
	}
	return ranges;
}

- (BOOL)rangeIsWholeWord:(NSRange)range inString:(NSString *)text {
	NSMutableCharacterSet *word = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[word addCharactersInString:@"_"];
	BOOL left = range.location == 0 || ![word characterIsMember:[text characterAtIndex:range.location - 1]];
	BOOL right = NSMaxRange(range) >= text.length || ![word characterIsMember:[text characterAtIndex:NSMaxRange(range)]];
	return left && right;
}

- (NSString *)stringByReplacingMatchesInString:(NSString *)text count:(NSInteger *)count error:(NSError **)error {
	NSArray<NSValue *> *ranges = [self rangesInString:text error:error];
	if (count) *count = ranges.count;
	if (ranges.count == 0 || (error && *error)) return text;
	if (self.searchMode == NppMacSearchModeRegex) {
		NSRegularExpressionOptions options = self.matchCaseCheckbox.state == NSControlStateValueOn ? 0 : NSRegularExpressionCaseInsensitive;
		if (self.dotMatchesNewlineCheckbox.state == NSControlStateValueOn) options |= NSRegularExpressionDotMatchesLineSeparators;
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[self searchText] options:options error:error];
		return [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length)
			withTemplate:[self foundationRegexReplacementText]];
	}
	NSMutableString *result = [text mutableCopy];
	for (NSValue *value in ranges.reverseObjectEnumerator) {
		[result replaceCharactersInRange:value.rangeValue withString:[self replacementText]];
	}
	return result;
}

- (void)findAllOpenedAction:(id)sender {
	(void)sender;
	NSArray<NppMacFindDocumentSnapshot *> *documents = self.openDocumentsProvider ? self.openDocumentsProvider() : @[];
	NSMutableString *output = [NSMutableString string];
	NSInteger total = 0;
	for (NppMacFindDocumentSnapshot *document in documents) {
		NSError *error = nil;
		NSArray<NSValue *> *ranges = [self rangesInString:document.text ?: @"" error:&error];
		if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
		for (NSValue *value in ranges) {
			NSUInteger line = 1;
			for (NSUInteger i = 0; i < value.rangeValue.location; ++i) if ([document.text characterAtIndex:i] == '\n') line++;
			[output appendFormat:NppL("find.result.openedLine"), document.displayName, (unsigned long)line];
		}
		total += ranges.count;
	}
	self.resultsView.string = output;
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.openedResults"),
		(long)total, (long)documents.count];
}

- (void)replaceAllOpenedAction:(id)sender {
	(void)sender;
	NSArray<NppMacFindDocumentSnapshot *> *documents = self.openDocumentsProvider ? self.openDocumentsProvider() : @[];
	NSInteger total = 0;
	for (NppMacFindDocumentSnapshot *document in documents) {
		NSError *error = nil;
		NSInteger count = 0;
		NSString *replacement = [self stringByReplacingMatchesInString:document.text ?: @"" count:&count error:&error];
		if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
		if (count > 0 && self.replaceOpenDocumentHandler) {
			self.replaceOpenDocumentHandler(document.documentIndex, replacement);
		}
		total += count;
	}
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.replacedOpened"), (long)total];
}

- (BOOL)fileURLMatchesFilters:(NSURL *)url {
	NSString *filters = self.filtersField.stringValue.length > 0 ? self.filtersField.stringValue : @"*";
	NSArray<NSString *> *parts = [filters componentsSeparatedByCharactersInSet:
		[NSCharacterSet characterSetWithCharactersInString:@";, \t\n"]];
	for (NSString *filter in parts) {
		NSPredicate *predicate = filter.length > 0 ? [NSPredicate predicateWithFormat:@"SELF LIKE[c] %@", filter] : nil;
		if (predicate && [predicate evaluateWithObject:url.lastPathComponent]) {
			return YES;
		}
	}
	return NO;
}

- (NSArray<NSURL *> *)candidateFileURLs {
	NSURL *directory = [NSURL fileURLWithPath:[self.directoryField.stringValue stringByExpandingTildeInPath] isDirectory:YES];
	NSDirectoryEnumerationOptions options = self.hiddenFoldersCheckbox.state == NSControlStateValueOn
		? 0 : NSDirectoryEnumerationSkipsHiddenFiles;
	NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager enumeratorAtURL:directory
		includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:options errorHandler:^BOOL(NSURL *url, NSError *error) {
		(void)url; (void)error; return YES;
	}];
	NSMutableArray<NSURL *> *files = [NSMutableArray array];
	for (NSURL *url in enumerator) {
		if (self.recursiveCheckbox.state != NSControlStateValueOn && enumerator.level > 1) {
			[enumerator skipDescendants];
			continue;
		}
		NSNumber *regular = nil;
		[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
		if (regular.boolValue && [self fileURLMatchesFilters:url]) [files addObject:url];
	}
	return files;
}

- (void)findInFilesAction:(id)sender {
	(void)sender;
	NSMutableString *output = [NSMutableString string];
	NSInteger total = 0;
	NSInteger searched = 0;
	for (NSURL *url in self.candidateFileURLs) {
		NSStringEncoding encoding = NSUTF8StringEncoding;
		NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:nil];
		if (!text) continue;
		searched++;
		NSError *error = nil;
		NSArray<NSValue *> *ranges = [self rangesInString:text error:&error];
		if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
		for (NSValue *value in ranges) {
			NSUInteger line = 1;
			for (NSUInteger i = 0; i < value.rangeValue.location; ++i) if ([text characterAtIndex:i] == '\n') line++;
			[output appendFormat:NppL("find.result.fileLine"), url.path, (unsigned long)line];
		}
		total += ranges.count;
	}
	self.resultsView.string = output;
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.fileResults"),
		(long)total, (long)searched];
}

- (void)replaceInFilesAction:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NppL("find.replaceFiles.title");
	alert.informativeText = NppL("find.replaceFiles.message");
	[alert addButtonWithTitle:NppL("common.replace")];
	[alert addButtonWithTitle:NppL("common.cancel")];
	if ([alert runModal] != NSAlertFirstButtonReturn) return;
	NSInteger total = 0;
	NSInteger changedFiles = 0;
	for (NSURL *url in self.candidateFileURLs) {
		NSStringEncoding encoding = NSUTF8StringEncoding;
		NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:nil];
		if (!text) continue;
		NSError *error = nil;
		NSInteger count = 0;
		NSString *replacement = [self stringByReplacingMatchesInString:text count:&count error:&error];
		if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
		if (count > 0 && [replacement writeToURL:url atomically:YES encoding:encoding error:&error]) {
			total += count;
			changedFiles++;
		}
	}
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.replacedFiles"),
		(long)total, (long)changedFiles];
}

- (void)browseDirectoryAction:(id)sender {
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseDirectories = YES;
	panel.canChooseFiles = NO;
	panel.allowsMultipleSelection = NO;
	if ([panel runModal] == NSModalResponseOK) self.directoryField.stringValue = panel.URL.path;
}

- (void)copyMarkedTextAction:(id)sender {
	(void)sender;
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	for (NSValue *value in self.markedRanges) [parts addObject:[self textForByteRange:value.rangeValue]];
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:[parts componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
	self.statusLabel.stringValue = [NSString stringWithFormat:NppL("find.status.copied"), (long)parts.count];
}

- (void)findNextAction:(id)sender { (void)sender; [self findNext]; }
- (void)findPreviousAction:(id)sender { (void)sender; [self findPrevious]; }
- (void)replaceCurrentAction:(id)sender { (void)sender; [self replaceCurrent]; }
- (void)replaceAllAction:(id)sender { (void)sender; [self replaceAll]; }
- (void)countAction:(id)sender { (void)sender; [self countAll]; }
- (void)markAllAction:(id)sender { (void)sender; [self markAll]; }
- (void)clearMarksAction:(id)sender { (void)sender; [self clearAllMarks]; }

@end
