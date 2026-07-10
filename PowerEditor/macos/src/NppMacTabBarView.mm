#import "NppMacTabBarView.h"
#import "NppMacLocalization.h"

static const CGFloat kTabBarHeight = 32.0;
static const CGFloat kTabMinimumWidth = 110.0;
static const CGFloat kTabMaximumWidth = 240.0;
static const CGFloat kScrollButtonWidth = 21.0;
static const CGFloat kNewTabButtonWidth = 32.0;

@implementation NppMacTabItem
@end

@class NppMacTabStripView;

@protocol NppMacTabStripViewDelegate <NSObject>
- (void)tabStripView:(NppMacTabStripView *)strip didSelectTabAtIndex:(NSUInteger)index;
- (void)tabStripView:(NppMacTabStripView *)strip didRequestCloseTabAtIndex:(NSUInteger)index;
- (void)tabStripViewDidRequestNewTab:(NppMacTabStripView *)strip;
- (void)tabStripView:(NppMacTabStripView *)strip
	didMoveTabFromIndex:(NSUInteger)sourceIndex
	toIndex:(NSUInteger)destinationIndex;
@end

@interface NppMacTabStripView : NSView
@property(nonatomic, weak) id<NppMacTabStripViewDelegate> delegate;
@property(nonatomic, copy) NSArray<NppMacTabItem *> *items;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, copy) NSArray<NSValue *> *tabRects;
@property(nonatomic) NSRect newTabRect;
- (CGFloat)preferredWidth;
- (void)rebuildLayout;
@end

@interface NppMacTabStripView ()
@property(nonatomic) NSInteger hoveredIndex;
@property(nonatomic) NSInteger pressedIndex;
@property(nonatomic) NSInteger dragTargetIndex;
@property(nonatomic) BOOL closeButtonHovered;
@property(nonatomic) BOOL closeButtonPressed;
@property(nonatomic) BOOL newTabHovered;
@property(nonatomic) BOOL newTabPressed;
@property(nonatomic) NSPoint mouseDownPoint;
@property(nonatomic, strong) NSTrackingArea *trackingArea;
@property(nonatomic, strong) NSImage *savedImage;
@property(nonatomic, strong) NSImage *unsavedImage;
@property(nonatomic, strong) NSImage *closeImage;
@property(nonatomic, strong) NSImage *closeHoverImage;
@property(nonatomic, strong) NSImage *closeTabHoverImage;
@property(nonatomic, strong) NSImage *closePressedImage;
@property(nonatomic, strong) NSImage *darkUnsavedImage;
@property(nonatomic, strong) NSImage *darkCloseImage;
@property(nonatomic, strong) NSImage *darkCloseHoverImage;
@property(nonatomic, strong) NSImage *darkCloseTabHoverImage;
@property(nonatomic, strong) NSImage *darkClosePressedImage;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *toolTipTags;
@end

@implementation NppMacTabStripView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_items = @[];
		_selectedIndex = NSNotFound;
		_hoveredIndex = NSNotFound;
		_pressedIndex = NSNotFound;
		_dragTargetIndex = NSNotFound;
		_toolTipTags = [NSMutableArray array];
		NSBundle *bundle = NSBundle.mainBundle;
		_savedImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-saved" ofType:@"png"]];
		_unsavedImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-unsaved" ofType:@"png"]];
		_closeImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-close" ofType:@"png"]];
		_closeHoverImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-close-hover" ofType:@"png"]];
		_closeTabHoverImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-close-tab-hover" ofType:@"png"]];
		_closePressedImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-close-pressed" ofType:@"png"]];
		_darkUnsavedImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-dark-unsaved" ofType:@"png"]];
		_darkCloseImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-dark-close" ofType:@"png"]];
		_darkCloseHoverImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-dark-close-hover" ofType:@"png"]];
		_darkCloseTabHoverImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-dark-close-tab-hover" ofType:@"png"]];
		_darkClosePressedImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"tab-dark-close-pressed" ofType:@"png"]];
	}
	return self;
}

- (BOOL)isFlipped {
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
	(void)event;
	return YES;
}

- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	if (self.trackingArea) {
		[self removeTrackingArea:self.trackingArea];
	}
	self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
		options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
		owner:self
		userInfo:nil];
	[self addTrackingArea:self.trackingArea];
}

- (void)setItems:(NSArray<NppMacTabItem *> *)items {
	_items = [items copy] ?: @[];
	if (_selectedIndex >= (NSInteger)_items.count) {
		_selectedIndex = _items.count == 0 ? NSNotFound : (NSInteger)_items.count - 1;
	}
	[self rebuildLayout];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
	_selectedIndex = selectedIndex;
	[self setNeedsDisplay:YES];
}

- (NSDictionary<NSAttributedStringKey, id> *)titleAttributesForSelected:(BOOL)selected {
	return @{
		NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:selected ? NSFontWeightMedium : NSFontWeightRegular],
		NSForegroundColorAttributeName: selected ? NSColor.labelColor : NSColor.secondaryLabelColor
	};
}

- (CGFloat)preferredWidth {
	CGFloat total = kNewTabButtonWidth;
	for (NppMacTabItem *item in self.items) {
		CGFloat titleWidth = ceil([item.title sizeWithAttributes:[self titleAttributesForSelected:NO]].width);
		total += MIN(kTabMaximumWidth, MAX(kTabMinimumWidth, titleWidth + 58.0));
	}
	return total;
}

- (void)rebuildLayout {
	NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity:self.items.count];
	CGFloat x = 0.0;
	for (NppMacTabItem *item in self.items) {
		CGFloat titleWidth = ceil([item.title sizeWithAttributes:[self titleAttributesForSelected:NO]].width);
		CGFloat width = MIN(kTabMaximumWidth, MAX(kTabMinimumWidth, titleWidth + 58.0));
		[rects addObject:[NSValue valueWithRect:NSMakeRect(x, 0.0, width, kTabBarHeight)]];
		x += width;
	}
	self.tabRects = rects;
	self.newTabRect = NSMakeRect(x, 0.0, kNewTabButtonWidth, kTabBarHeight);
	[self setFrameSize:NSMakeSize(MAX(NSMaxX(self.newTabRect), self.superview.bounds.size.width), kTabBarHeight)];

	for (NSNumber *tag in self.toolTipTags) {
		[self removeToolTip:tag.integerValue];
	}
	[self.toolTipTags removeAllObjects];
	[self.items enumerateObjectsUsingBlock:^(NppMacTabItem *item, NSUInteger index, BOOL *stop) {
		(void)stop;
		NSToolTipTag tag = [self addToolTipRect:self.tabRects[index].rectValue
			owner:self
			userData:(__bridge void *)item];
		[self.toolTipTags addObject:@(tag)];
	}];
	NSToolTipTag newTabTag = [self addToolTipRect:self.newTabRect owner:self userData:NULL];
	[self.toolTipTags addObject:@(newTabTag)];
	[self setNeedsDisplay:YES];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
	(void)view;
	(void)tag;
	(void)point;
	if (!data) {
		return NppL("tooltip.newDocument");
	}
	NppMacTabItem *item = (__bridge NppMacTabItem *)data;
	return item.toolTip.length > 0 ? item.toolTip : item.title;
}

- (BOOL)isDarkAppearance {
	if (@available(macOS 10.14, *)) {
		NSAppearanceName match = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
			NSAppearanceNameAqua, NSAppearanceNameDarkAqua
		]];
		return [match isEqualToString:NSAppearanceNameDarkAqua];
	}
	return NO;
}

- (NSRect)closeRectForTabRect:(NSRect)tabRect {
	return NSMakeRect(NSMaxX(tabRect) - 20.0, floor((kTabBarHeight - 11.0) / 2.0) + 2.0, 11.0, 11.0);
}

- (void)drawFallbackDocumentIconInRect:(NSRect)rect dirty:(BOOL)dirty {
	NSColor *fill = dirty ? [NSColor colorWithCalibratedRed:0.94 green:0.76 blue:0.24 alpha:1.0]
		: [NSColor colorWithCalibratedWhite:[self isDarkAppearance] ? 0.65 : 0.94 alpha:1.0];
	[fill setFill];
	[[NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.5, 0.5)] fill];
	[NSColor.tertiaryLabelColor setStroke];
	[[NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.5, 0.5)] stroke];
}

- (void)drawFallbackCloseInRect:(NSRect)rect highlighted:(BOOL)highlighted {
	NSBezierPath *path = [NSBezierPath bezierPath];
	path.lineWidth = 1.25;
	[path moveToPoint:NSMakePoint(NSMinX(rect) + 2.0, NSMinY(rect) + 2.0)];
	[path lineToPoint:NSMakePoint(NSMaxX(rect) - 2.0, NSMaxY(rect) - 2.0)];
	[path moveToPoint:NSMakePoint(NSMaxX(rect) - 2.0, NSMinY(rect) + 2.0)];
	[path lineToPoint:NSMakePoint(NSMinX(rect) + 2.0, NSMaxY(rect) - 2.0)];
	[highlighted ? NSColor.labelColor : NSColor.secondaryLabelColor setStroke];
	[path stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	BOOL dark = [self isDarkAppearance];
	NSColor *barBackground = dark ? [NSColor colorWithCalibratedWhite:0.13 alpha:1.0]
		: [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
	NSColor *activeBackground = dark ? [NSColor colorWithCalibratedWhite:0.20 alpha:1.0]
		: NSColor.controlBackgroundColor;
	NSColor *inactiveBackground = dark ? [NSColor colorWithCalibratedWhite:0.15 alpha:1.0]
		: [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
	NSColor *hoverBackground = dark ? [NSColor colorWithCalibratedWhite:0.20 alpha:1.0]
		: [NSColor colorWithCalibratedWhite:0.82 alpha:1.0];
	NSColor *separator = dark ? [NSColor colorWithCalibratedWhite:0.29 alpha:1.0]
		: [NSColor colorWithCalibratedWhite:0.57 alpha:1.0];
	NSColor *activeTopBar = self.window.isKeyWindow
		? [NSColor colorWithCalibratedRed:250.0 / 255.0 green:170.0 / 255.0 blue:60.0 / 255.0 alpha:1.0]
		: [NSColor colorWithCalibratedRed:250.0 / 255.0 green:210.0 / 255.0 blue:150.0 / 255.0 alpha:1.0];
	[barBackground setFill];
	NSRectFill(self.bounds);

	[self.items enumerateObjectsUsingBlock:^(NppMacTabItem *item, NSUInteger index, BOOL *stop) {
		(void)stop;
		NSRect tabRect = self.tabRects[index].rectValue;
		BOOL selected = (NSInteger)index == self.selectedIndex;
		BOOL hovered = (NSInteger)index == self.hoveredIndex;
		[(selected ? activeBackground : (hovered ? hoverBackground : inactiveBackground)) setFill];
		NSRectFill(tabRect);

		if (selected) {
			[activeTopBar setFill];
			NSRectFill(NSMakeRect(NSMinX(tabRect), NSMinY(tabRect), NSWidth(tabRect), 4.0));
		}

		[separator setFill];
		NSRectFill(NSMakeRect(NSMaxX(tabRect) - 1.0, 4.0, 1.0, NSHeight(tabRect) - 4.0));

		NSRect iconRect = NSMakeRect(NSMinX(tabRect) + 8.0, 9.0, 16.0, 16.0);
		NSImage *documentImage = item.dirty ? (dark ? (self.darkUnsavedImage ?: self.unsavedImage) : self.unsavedImage)
			: self.savedImage;
		if (documentImage) {
			[documentImage drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
				fraction:selected ? 1.0 : 0.72 respectFlipped:YES hints:nil];
		} else {
			[self drawFallbackDocumentIconInRect:iconRect dirty:item.dirty];
		}

		NSRect closeRect = [self closeRectForTabRect:tabRect];
		BOOL closeHovered = hovered && self.closeButtonHovered;
		NSImage *closeImage = dark ? (self.darkCloseImage ?: self.closeImage) : self.closeImage;
		if (hovered && !closeHovered) {
			closeImage = dark ? (self.darkCloseTabHoverImage ?: closeImage) : (self.closeTabHoverImage ?: closeImage);
		}
		if (closeHovered) {
			if (dark) {
				closeImage = self.closeButtonPressed ? (self.darkClosePressedImage ?: self.darkCloseHoverImage ?: closeImage)
					: (self.darkCloseHoverImage ?: closeImage);
			} else {
				closeImage = self.closeButtonPressed ? (self.closePressedImage ?: self.closeHoverImage)
					: (self.closeHoverImage ?: closeImage);
			}
		}
		if (closeImage) {
			[closeImage drawInRect:closeRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
				fraction:1.0 respectFlipped:YES hints:nil];
		} else {
			[self drawFallbackCloseInRect:closeRect highlighted:closeHovered];
		}

		NSRect titleRect = NSMakeRect(NSMaxX(iconRect) + 6.0, 7.0,
			NSMinX(closeRect) - NSMaxX(iconRect) - 12.0, 18.0);
		[item.title drawWithRect:titleRect
			options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin
			attributes:[self titleAttributesForSelected:selected]];
	}];

	if (self.newTabHovered || self.newTabPressed) {
		[(self.newTabPressed ? activeBackground : hoverBackground) setFill];
		NSRectFill(self.newTabRect);
	}
	[separator setFill];
	NSRectFill(NSMakeRect(NSMaxX(self.newTabRect) - 1.0, 4.0, 1.0, NSHeight(self.newTabRect) - 4.0));
	NSColor *plusColor = self.newTabPressed ? NSColor.labelColor : NSColor.secondaryLabelColor;
	[plusColor setStroke];
	NSBezierPath *plus = [NSBezierPath bezierPath];
	plus.lineWidth = 1.5;
	CGFloat plusCenterX = NSMidX(self.newTabRect);
	CGFloat plusCenterY = NSMidY(self.newTabRect) + 1.0;
	[plus moveToPoint:NSMakePoint(plusCenterX - 5.0, plusCenterY)];
	[plus lineToPoint:NSMakePoint(plusCenterX + 5.0, plusCenterY)];
	[plus moveToPoint:NSMakePoint(plusCenterX, plusCenterY - 5.0)];
	[plus lineToPoint:NSMakePoint(plusCenterX, plusCenterY + 5.0)];
	[plus stroke];

	[separator setFill];
	NSRectFill(NSMakeRect(0.0, kTabBarHeight - 1.0, NSWidth(self.bounds), 1.0));
	if (self.dragTargetIndex != NSNotFound && self.dragTargetIndex < (NSInteger)self.tabRects.count) {
		NSRect target = self.tabRects[(NSUInteger)self.dragTargetIndex].rectValue;
		[activeTopBar setFill];
		NSRectFill(NSMakeRect(NSMinX(target), 4.0, 2.0, kTabBarHeight - 5.0));
	}
}

- (NSInteger)tabIndexAtPoint:(NSPoint)point {
	for (NSUInteger index = 0; index < self.tabRects.count; ++index) {
		if (NSPointInRect(point, self.tabRects[index].rectValue)) {
			return (NSInteger)index;
		}
	}
	return NSNotFound;
}

- (void)updateHoverAtPoint:(NSPoint)point {
	NSInteger index = [self tabIndexAtPoint:point];
	BOOL overNewTab = NSPointInRect(point, self.newTabRect);
	BOOL overClose = index != NSNotFound && NSPointInRect(point,
		[self closeRectForTabRect:self.tabRects[(NSUInteger)index].rectValue]);
	if (index != self.hoveredIndex || overClose != self.closeButtonHovered || overNewTab != self.newTabHovered) {
		self.hoveredIndex = index;
		self.closeButtonHovered = overClose;
		self.newTabHovered = overNewTab;
		[self setNeedsDisplay:YES];
	}
}

- (void)mouseMoved:(NSEvent *)event {
	[self updateHoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)event {
	(void)event;
	self.hoveredIndex = NSNotFound;
	self.closeButtonHovered = NO;
	self.newTabHovered = NO;
	[self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	self.mouseDownPoint = point;
	self.pressedIndex = [self tabIndexAtPoint:point];
	self.newTabPressed = NSPointInRect(point, self.newTabRect);
	self.dragTargetIndex = NSNotFound;
	self.closeButtonPressed = self.pressedIndex != NSNotFound && NSPointInRect(point,
		[self closeRectForTabRect:self.tabRects[(NSUInteger)self.pressedIndex].rectValue]);
	if (self.pressedIndex != NSNotFound && !self.closeButtonPressed) {
		[self.delegate tabStripView:self didSelectTabAtIndex:(NSUInteger)self.pressedIndex];
	}
	[self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
	if (self.pressedIndex == NSNotFound || self.closeButtonPressed || self.newTabPressed) {
		return;
	}
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	if (fabs(point.x - self.mouseDownPoint.x) < 4.0 && fabs(point.y - self.mouseDownPoint.y) < 4.0) {
		return;
	}
	NSInteger target = [self tabIndexAtPoint:point];
	if (target != NSNotFound) {
		self.dragTargetIndex = target;
		[self setNeedsDisplay:YES];
	}
}

- (void)mouseUp:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	NSInteger releasedIndex = [self tabIndexAtPoint:point];
	if (self.newTabPressed && NSPointInRect(point, self.newTabRect)) {
		[self.delegate tabStripViewDidRequestNewTab:self];
	} else if (self.closeButtonPressed && releasedIndex == self.pressedIndex && releasedIndex != NSNotFound &&
		NSPointInRect(point, [self closeRectForTabRect:self.tabRects[(NSUInteger)releasedIndex].rectValue])) {
		[self.delegate tabStripView:self didRequestCloseTabAtIndex:(NSUInteger)releasedIndex];
	} else if (self.dragTargetIndex != NSNotFound && self.dragTargetIndex != self.pressedIndex) {
		[self.delegate tabStripView:self didMoveTabFromIndex:(NSUInteger)self.pressedIndex
			toIndex:(NSUInteger)self.dragTargetIndex];
	}
	self.pressedIndex = NSNotFound;
	self.dragTargetIndex = NSNotFound;
	self.closeButtonPressed = NO;
	self.newTabPressed = NO;
	[self updateHoverAtPoint:point];
	[self setNeedsDisplay:YES];
}

- (void)otherMouseDown:(NSEvent *)event {
	if (event.buttonNumber != 2) {
		return;
	}
	NSInteger index = [self tabIndexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
	if (index != NSNotFound) {
		[self.delegate tabStripView:self didRequestCloseTabAtIndex:(NSUInteger)index];
	}
}

@end

@interface NppMacTabBarView () <NppMacTabStripViewDelegate>
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NppMacTabStripView *stripView;
@property(nonatomic, strong) NSButton *scrollLeftButton;
@property(nonatomic, strong) NSButton *scrollRightButton;
@end

@implementation NppMacTabBarView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_selectedIndex = NSNotFound;
		self.wantsLayer = YES;
		_scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
		_scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_scrollView.borderType = NSNoBorder;
		_scrollView.drawsBackground = NO;
		_scrollView.hasHorizontalScroller = NO;
		_scrollView.hasVerticalScroller = NO;
		_stripView = [[NppMacTabStripView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(frameRect), kTabBarHeight)];
		_stripView.delegate = self;
		_scrollView.documentView = _stripView;
		[self addSubview:_scrollView];

		_scrollLeftButton = [self scrollButtonWithImageName:NSImageNameGoLeftTemplate action:@selector(scrollLeft:)];
		_scrollRightButton = [self scrollButtonWithImageName:NSImageNameGoRightTemplate action:@selector(scrollRight:)];
		[self addSubview:_scrollLeftButton];
		[self addSubview:_scrollRightButton];
	}
	return self;
}

- (BOOL)isFlipped {
	return YES;
}

- (NSButton *)scrollButtonWithImageName:(NSImageName)imageName action:(SEL)action {
	NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
	button.bezelStyle = NSBezelStyleSmallSquare;
	button.image = [NSImage imageNamed:imageName];
	button.imagePosition = NSImageOnly;
	button.target = self;
	button.action = action;
	button.hidden = YES;
	return button;
}

- (void)layout {
	[super layout];
	BOOL overflow = [self.stripView preferredWidth] > NSWidth(self.bounds);
	CGFloat controlsWidth = overflow ? kScrollButtonWidth * 2.0 : 0.0;
	self.scrollView.frame = NSMakeRect(0.0, 0.0, MAX(0.0, NSWidth(self.bounds) - controlsWidth), NSHeight(self.bounds));
	self.scrollLeftButton.frame = NSMakeRect(NSWidth(self.bounds) - controlsWidth, 0.0, kScrollButtonWidth, NSHeight(self.bounds));
	self.scrollRightButton.frame = NSMakeRect(NSWidth(self.bounds) - kScrollButtonWidth, 0.0, kScrollButtonWidth, NSHeight(self.bounds));
	self.scrollLeftButton.hidden = !overflow;
	self.scrollRightButton.hidden = !overflow;
	[self.stripView rebuildLayout];
	[self updateScrollButtons];
}

- (void)setItems:(NSArray<NppMacTabItem *> *)items {
	_items = [items copy] ?: @[];
	self.stripView.items = _items;
	[self setNeedsLayout:YES];
	[self layoutSubtreeIfNeeded];
	[self revealSelectedTab];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
	_selectedIndex = selectedIndex;
	self.stripView.selectedIndex = selectedIndex;
	[self revealSelectedTab];
}

- (void)revealSelectedTab {
	if (self.selectedIndex == NSNotFound || self.selectedIndex >= (NSInteger)self.stripView.tabRects.count) {
		return;
	}
	NSRect revealRect = self.stripView.tabRects[(NSUInteger)self.selectedIndex].rectValue;
	if (self.selectedIndex == (NSInteger)self.items.count - 1) {
		revealRect = NSUnionRect(revealRect, self.stripView.newTabRect);
	}
	[self.stripView scrollRectToVisible:revealRect];
	[self updateScrollButtons];
}

- (void)scrollLeft:(id)sender {
	(void)sender;
	NSClipView *clipView = self.scrollView.contentView;
	NSPoint origin = clipView.bounds.origin;
	origin.x = MAX(0.0, origin.x - MAX(kTabMinimumWidth, NSWidth(clipView.bounds) * 0.6));
	[clipView scrollToPoint:origin];
	[self.scrollView reflectScrolledClipView:clipView];
	[self updateScrollButtons];
}

- (void)scrollRight:(id)sender {
	(void)sender;
	NSClipView *clipView = self.scrollView.contentView;
	CGFloat maxX = MAX(0.0, NSWidth(self.stripView.frame) - NSWidth(clipView.bounds));
	NSPoint origin = clipView.bounds.origin;
	origin.x = MIN(maxX, origin.x + MAX(kTabMinimumWidth, NSWidth(clipView.bounds) * 0.6));
	[clipView scrollToPoint:origin];
	[self.scrollView reflectScrolledClipView:clipView];
	[self updateScrollButtons];
}

- (void)updateScrollButtons {
	if (self.scrollLeftButton.hidden) {
		return;
	}
	NSClipView *clipView = self.scrollView.contentView;
	CGFloat maxX = MAX(0.0, NSWidth(self.stripView.frame) - NSWidth(clipView.bounds));
	self.scrollLeftButton.enabled = NSMinX(clipView.bounds) > 0.5;
	self.scrollRightButton.enabled = NSMinX(clipView.bounds) < maxX - 0.5;
}

- (void)tabStripView:(NppMacTabStripView *)strip didSelectTabAtIndex:(NSUInteger)index {
	(void)strip;
	self.selectedIndex = (NSInteger)index;
	[self.delegate tabBarView:self didSelectTabAtIndex:index];
}

- (void)tabStripView:(NppMacTabStripView *)strip didRequestCloseTabAtIndex:(NSUInteger)index {
	(void)strip;
	[self.delegate tabBarView:self didRequestCloseTabAtIndex:index];
}

- (void)tabStripViewDidRequestNewTab:(NppMacTabStripView *)strip {
	(void)strip;
	[self.delegate tabBarViewDidRequestNewTab:self];
}

- (void)tabStripView:(NppMacTabStripView *)strip
	didMoveTabFromIndex:(NSUInteger)sourceIndex
	toIndex:(NSUInteger)destinationIndex {
	(void)strip;
	[self.delegate tabBarView:self didMoveTabFromIndex:sourceIndex toIndex:destinationIndex];
}

@end
