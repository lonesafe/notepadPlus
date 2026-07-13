#import "NppMacToolBarView.h"

#import "NppMacLocalization.h"

@interface NppMacToolBarItem : NSObject
@property(nonatomic, copy) NSString *iconName;
@property(nonatomic, copy) NSString *localizationKey;
@property(nonatomic) SEL action;
@property(nonatomic) BOOL toggle;
@end

@implementation NppMacToolBarItem
@end

@interface NppMacToolBarButton : NSButton
@property(nonatomic) BOOL mouseHovering;
@property(nonatomic) BOOL mousePressed;
@property(nonatomic, strong) NSTrackingArea *hoverTrackingArea;
- (void)refreshBackground;
@end

@implementation NppMacToolBarButton

- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	if (self.hoverTrackingArea) [self removeTrackingArea:self.hoverTrackingArea];
	NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
	self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
	[self addTrackingArea:self.hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
	(void)event;
	if (!self.enabled) return;
	self.mouseHovering = YES;
	[NSCursor.pointingHandCursor set];
	[self refreshBackground];
}

- (void)mouseExited:(NSEvent *)event {
	(void)event;
	self.mouseHovering = NO;
	self.mousePressed = NO;
	[NSCursor.arrowCursor set];
	[self refreshBackground];
}

- (void)mouseDown:(NSEvent *)event {
	if (!self.enabled) return;
	self.mousePressed = YES;
	[self refreshBackground];
	[super mouseDown:event];
	self.mousePressed = NO;
	[self refreshBackground];
}

- (void)setState:(NSControlStateValue)state {
	[super setState:state];
	[self refreshBackground];
}

- (void)setEnabled:(BOOL)enabled {
	[super setEnabled:enabled];
	if (!enabled) {
		self.mouseHovering = NO;
		self.mousePressed = NO;
	}
	[self refreshBackground];
}

- (void)refreshBackground {
	NSColor *color = NSColor.clearColor;
	if (self.enabled && self.mousePressed) {
		color = [NSColor.selectedControlColor colorWithAlphaComponent:0.28];
	} else if (self.enabled && self.state == NSControlStateValueOn) {
		color = [NSColor.selectedControlColor colorWithAlphaComponent:self.mouseHovering ? 0.26 : 0.18];
	} else if (self.enabled && self.mouseHovering) {
		color = [NSColor.labelColor colorWithAlphaComponent:0.10];
	}
	self.layer.backgroundColor = color.CGColor;
}

@end

@interface NppMacToolBarView ()
@property(nonatomic, weak) id actionTarget;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSStackView *stackView;
@property(nonatomic, copy) NSArray<NppMacToolBarItem *> *items;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *buttonsByAction;
@end

@implementation NppMacToolBarView

- (instancetype)initWithFrame:(NSRect)frame target:(id)target {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	_actionTarget = target;
	_buttonsByAction = [NSMutableDictionary dictionary];
	[self buildToolBar];
	return self;
}

- (BOOL)isFlipped { return YES; }

- (NppMacToolBarItem *)item:(NSString *)icon key:(NSString *)key action:(SEL)action toggle:(BOOL)toggle {
	NppMacToolBarItem *item = [[NppMacToolBarItem alloc] init];
	item.iconName = icon;
	item.localizationKey = key;
	item.action = action;
	item.toggle = toggle;
	return item;
}

- (void)buildToolBar {
	self.wantsLayer = YES;
	self.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;

	self.scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
	self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	self.scrollView.drawsBackground = NO;
	self.scrollView.borderType = NSNoBorder;
	self.scrollView.hasHorizontalScroller = YES;
	self.scrollView.autohidesScrollers = YES;
	self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
	[self addSubview:self.scrollView];

	self.stackView = [[NSStackView alloc] initWithFrame:NSMakeRect(6, 4, 0, 30)];
	self.stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	self.stackView.alignment = NSLayoutAttributeCenterY;
	self.stackView.spacing = 2;
	self.stackView.edgeInsets = NSEdgeInsetsMake(4, 6, 4, 6);

	NSArray *groups = @[
		@[
			[self item:@"new" key:@"menu.file.new" action:@selector(newDocument:) toggle:NO],
			[self item:@"open" key:@"menu.file.open" action:@selector(openDocument:) toggle:NO],
			[self item:@"save" key:@"menu.file.save" action:@selector(saveDocument:) toggle:NO],
			[self item:@"saveall" key:@"menu.file.saveAll" action:@selector(saveAllDocuments:) toggle:NO],
			[self item:@"close" key:@"menu.file.closeTab" action:@selector(closeDocument:) toggle:NO],
			[self item:@"closeall" key:@"menu.file.closeAll" action:@selector(closeAllDocuments:) toggle:NO],
			[self item:@"print" key:@"menu.file.print" action:@selector(printDocument:) toggle:NO]
		],
		@[
			[self item:@"cut" key:@"menu.edit.cut" action:@selector(cut:) toggle:NO],
			[self item:@"copy" key:@"menu.edit.copy" action:@selector(copy:) toggle:NO],
			[self item:@"paste" key:@"menu.edit.paste" action:@selector(paste:) toggle:NO]
		],
		@[
			[self item:@"undo" key:@"menu.edit.undo" action:@selector(undo:) toggle:NO],
			[self item:@"redo" key:@"menu.edit.redo" action:@selector(redo:) toggle:NO]
		],
		@[
			[self item:@"find" key:@"menu.search.find" action:@selector(findText:) toggle:NO],
			[self item:@"findrep" key:@"menu.search.replace" action:@selector(replaceText:) toggle:NO]
		],
		@[
			[self item:@"zoomIn" key:@"menu.view.zoomIn" action:@selector(zoomIn:) toggle:NO],
			[self item:@"zoomOut" key:@"menu.view.zoomOut" action:@selector(zoomOut:) toggle:NO]
		],
		@[
			[self item:@"wrap" key:@"menu.view.wordWrap" action:@selector(toggleWordWrap:) toggle:YES],
			[self item:@"allChars" key:@"menu.view.allCharacters" action:@selector(toggleAllCharacters:) toggle:YES],
			[self item:@"indentGuide" key:@"menu.view.indentGuide" action:@selector(toggleIndentGuides:) toggle:YES]
		],
		@[
			[self item:@"startrecord" key:@"menu.macro.start" action:@selector(startMacroRecording:) toggle:NO],
			[self item:@"stoprecord" key:@"menu.macro.stop" action:@selector(stopMacroRecording:) toggle:NO],
			[self item:@"playrecord" key:@"menu.macro.playback" action:@selector(playbackMacro:) toggle:NO],
			[self item:@"playrecord_m" key:@"menu.macro.runMultiple" action:@selector(runMacroMultipleTimes:) toggle:NO]
		]
	];

	NSMutableArray<NppMacToolBarItem *> *allItems = [NSMutableArray array];
	for (NSUInteger groupIndex = 0; groupIndex < groups.count; ++groupIndex) {
		if (groupIndex > 0) [self.stackView addArrangedSubview:[self separator]];
		for (NppMacToolBarItem *item in groups[groupIndex]) {
			[allItems addObject:item];
			[self.stackView addArrangedSubview:[self buttonForItem:item]];
		}
	}
	self.items = allItems;
	[self.stackView setFrameSize:self.stackView.fittingSize];
	self.scrollView.documentView = self.stackView;
	[self reloadLocalization];
}

- (NSView *)separator {
	NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 9, 24)];
	separator.boxType = NSBoxSeparator;
	[separator.widthAnchor constraintEqualToConstant:9].active = YES;
	[separator.heightAnchor constraintEqualToConstant:24].active = YES;
	return separator;
}

- (NSButton *)buttonForItem:(NppMacToolBarItem *)item {
	NppMacToolBarButton *button = [[NppMacToolBarButton alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
	button.title = @"";
	button.target = self.actionTarget;
	button.action = item.action;
	button.bordered = NO;
	button.imagePosition = NSImageOnly;
	button.imageScaling = NSImageScaleProportionallyDown;
	button.focusRingType = NSFocusRingTypeNone;
	button.buttonType = item.toggle ? NSButtonTypeToggle : NSButtonTypeMomentaryChange;
	button.wantsLayer = YES;
	button.layer.cornerRadius = 3;
	button.layer.masksToBounds = YES;
	NSURL *url = [NSBundle.mainBundle URLForResource:[@"toolbar-" stringByAppendingString:item.iconName]
		withExtension:@"png"];
	if (url) button.image = [[NSImage alloc] initWithContentsOfURL:url];
	[button.widthAnchor constraintEqualToConstant:28].active = YES;
	[button.heightAnchor constraintEqualToConstant:28].active = YES;
	self.buttonsByAction[NSStringFromSelector(item.action)] = button;
	return button;
}

- (void)reloadLocalization {
	for (NppMacToolBarItem *item in self.items) {
		NSButton *button = [self buttonForAction:item.action];
		button.toolTip = NppLocalizedString(item.localizationKey);
		button.accessibilityLabel = button.toolTip;
	}
}

- (NSButton *)buttonForAction:(SEL)action {
	return self.buttonsByAction[NSStringFromSelector(action)];
}

- (void)setButtonEnabled:(BOOL)enabled forAction:(SEL)action {
	[self buttonForAction:action].enabled = enabled;
}

- (void)setButtonOn:(BOOL)on forAction:(SEL)action {
	NppMacToolBarButton *button = (NppMacToolBarButton *)[self buttonForAction:action];
	button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
	[button refreshBackground];
}

@end
