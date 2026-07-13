#import "NppMacFileAssociationController.h"

#import "NppMacFileAssociationManager.h"
#import "NppMacLocalization.h"

static NSUserInterfaceItemIdentifier const typeColumnIdentifier = @"FileAssociationType";
static NSUserInterfaceItemIdentifier const extensionColumnIdentifier = @"FileAssociationExtensions";

@interface NppMacFileAssociationController () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NppMacFileAssociationManager *manager;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSTextField *descriptionLabel;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSButton *selectAllButton;
@property(nonatomic, strong) NSButton *clearButton;
@property(nonatomic, strong) NSButton *applyButton;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSMutableSet<NSString *> *selectedIdentifiers;
@end

@implementation NppMacFileAssociationController

- (instancetype)initWithManager:(NppMacFileAssociationManager *)manager {
	self = [super init];
	if (!self) return nil;
	_manager = manager;
	_selectedIdentifiers = [manager.selectedTypeIdentifiers mutableCopy];
	return self;
}

- (void)showPanel {
	if (!self.panel) [self buildPanel];
	self.selectedIdentifiers = [self.manager.selectedTypeIdentifiers mutableCopy];
	self.statusLabel.stringValue = @"";
	[self.tableView reloadData];
	if (!self.panel.visible) [self.panel center];
	[self.panel makeKeyAndOrderFront:nil];
}

- (void)buildPanel {
	self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 620, 500)
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
		backing:NSBackingStoreBuffered defer:NO];
	self.panel.floatingPanel = YES;
	self.panel.hidesOnDeactivate = NO;
	self.panel.releasedWhenClosed = NO;
	self.panel.minSize = NSMakeSize(520, 400);

	self.descriptionLabel = [self labelWithFrame:NSMakeRect(20, 452, 580, 30)];
	self.descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
	self.descriptionLabel.maximumNumberOfLines = 2;
	self.descriptionLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	[self.panel.contentView addSubview:self.descriptionLabel];

	self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
	self.tableView.delegate = self;
	self.tableView.dataSource = self;
	self.tableView.rowHeight = 30;
	self.tableView.usesAlternatingRowBackgroundColors = YES;
	NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:typeColumnIdentifier];
	typeColumn.width = 210;
	typeColumn.minWidth = 170;
	NSTableColumn *extensionColumn = [[NSTableColumn alloc] initWithIdentifier:extensionColumnIdentifier];
	extensionColumn.width = 350;
	extensionColumn.minWidth = 220;
	[self.tableView addTableColumn:typeColumn];
	[self.tableView addTableColumn:extensionColumn];

	NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 78, 580, 360)];
	scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scrollView.borderType = NSBezelBorder;
	scrollView.hasVerticalScroller = YES;
	scrollView.documentView = self.tableView;
	[self.panel.contentView addSubview:scrollView];

	self.selectAllButton = [self buttonWithFrame:NSMakeRect(20, 38, 90, 30) action:@selector(selectAll:)];
	self.clearButton = [self buttonWithFrame:NSMakeRect(116, 38, 90, 30) action:@selector(clearSelection:)];
	self.applyButton = [self buttonWithFrame:NSMakeRect(480, 38, 120, 30) action:@selector(applyAssociations:)];
	self.applyButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
	[self.panel.contentView addSubview:self.selectAllButton];
	[self.panel.contentView addSubview:self.clearButton];
	[self.panel.contentView addSubview:self.applyButton];

	self.statusLabel = [self labelWithFrame:NSMakeRect(20, 10, 580, 22)];
	self.statusLabel.textColor = NSColor.secondaryLabelColor;
	self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
	[self.panel.contentView addSubview:self.statusLabel];
	[self reloadLocalization];
}

- (NSTextField *)labelWithFrame:(NSRect)frame {
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	label.bezeled = NO;
	label.drawsBackground = NO;
	label.editable = NO;
	label.selectable = NO;
	return label;
}

- (NSButton *)buttonWithFrame:(NSRect)frame action:(SEL)action {
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	button.bezelStyle = NSBezelStyleRounded;
	button.target = self;
	button.action = action;
	return button;
}

- (void)reloadLocalization {
	if (!self.panel) return;
	self.panel.title = NppL("fileAssociation.title");
	self.descriptionLabel.stringValue = NppL("fileAssociation.description");
	self.tableView.tableColumns[0].title = NppL("fileAssociation.column.type");
	self.tableView.tableColumns[1].title = NppL("fileAssociation.column.extensions");
	self.selectAllButton.title = NppL("fileAssociation.selectAll");
	self.clearButton.title = NppL("fileAssociation.clear");
	self.applyButton.title = NppL("fileAssociation.apply");
	[self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	(void)tableView;
	return self.manager.supportedTypes.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NppMacFileAssociationType *type = self.manager.supportedTypes[(NSUInteger)row];
	if ([tableColumn.identifier isEqual:typeColumnIdentifier]) {
		NSButton *checkbox = [tableView makeViewWithIdentifier:typeColumnIdentifier owner:self];
		if (![checkbox isKindOfClass:NSButton.class]) {
			checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(typeSelectionChanged:)];
			checkbox.identifier = typeColumnIdentifier;
		}
		checkbox.title = NppLocalizedString(type.localizationKey);
		checkbox.tag = row;
		checkbox.state = [self.selectedIdentifiers containsObject:type.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
		return checkbox;
	}
	NSTextField *label = [tableView makeViewWithIdentifier:extensionColumnIdentifier owner:self];
	if (![label isKindOfClass:NSTextField.class]) {
		label = [self labelWithFrame:NSZeroRect];
		label.identifier = extensionColumnIdentifier;
		label.font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12];
		label.textColor = NSColor.secondaryLabelColor;
	}
	label.stringValue = [type.extensions componentsJoinedByString:@", "];
	return label;
}

- (void)typeSelectionChanged:(NSButton *)sender {
	if (sender.tag < 0 || sender.tag >= (NSInteger)self.manager.supportedTypes.count) return;
	NSString *identifier = self.manager.supportedTypes[(NSUInteger)sender.tag].identifier;
	if (sender.state == NSControlStateValueOn) [self.selectedIdentifiers addObject:identifier];
	else [self.selectedIdentifiers removeObject:identifier];
}

- (void)selectAll:(id)sender {
	(void)sender;
	[self.selectedIdentifiers addObjectsFromArray:[self.manager.supportedTypes valueForKey:@"identifier"]];
	[self.tableView reloadData];
}

- (void)clearSelection:(id)sender {
	(void)sender;
	[self.selectedIdentifiers removeAllObjects];
	[self.tableView reloadData];
}

- (void)applyAssociations:(id)sender {
	(void)sender;
	self.applyButton.enabled = NO;
	self.statusLabel.textColor = NSColor.secondaryLabelColor;
	self.statusLabel.stringValue = NppL("fileAssociation.applying");
	[self.manager applySelectedTypeIdentifiers:self.selectedIdentifiers completion:^(NSError *error) {
		self.applyButton.enabled = YES;
		self.statusLabel.textColor = error ? NSColor.systemRedColor : NSColor.systemGreenColor;
		self.statusLabel.stringValue = error ? [NSString stringWithFormat:NppL("fileAssociation.failed"), error.localizedDescription]
			: NppL("fileAssociation.success");
	}];
}

@end
