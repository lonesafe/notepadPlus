#import "NppMacPreferencesController.h"
#import "NppMacLocalization.h"

static NSString *const fontNameKey = @"NppMacEditorFontName";
static NSString *const fontSizeKey = @"NppMacEditorFontSize";
static NSString *const tabWidthKey = @"NppMacEditorTabWidth";
static NSString *const useTabsKey = @"NppMacEditorUseTabs";
static NSString *const showLineNumbersKey = @"NppMacEditorShowLineNumbers";
static NSString *const wrapLinesKey = @"NppMacEditorWrapLines";
static NSString *const alwaysOnTopKey = @"NppMacWindowAlwaysOnTop";
static NSString *const languageKey = @"NppMacInterfaceLanguage";

@interface NppMacPreferencesController ()
@property(nonatomic, strong) NSUserDefaults *userDefaults;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSPopUpButton *fontPopup;
@property(nonatomic, strong) NSPopUpButton *languagePopup;
@property(nonatomic, strong) NSTextField *fontSizeField;
@property(nonatomic, strong) NSStepper *fontSizeStepper;
@property(nonatomic, strong) NSTextField *tabWidthField;
@property(nonatomic, strong) NSStepper *tabWidthStepper;
@property(nonatomic, strong) NSButton *useTabsCheckbox;
@property(nonatomic, strong) NSButton *lineNumbersCheckbox;
@property(nonatomic, strong) NSButton *wrapLinesCheckbox;
@end

@implementation NppMacPreferencesController

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
	self = [super init];
	if (self) {
		_userDefaults = userDefaults;
		[_userDefaults registerDefaults:@{
			fontNameKey: @"Menlo",
			fontSizeKey: @13,
			tabWidthKey: @4,
			useTabsKey: @NO,
			showLineNumbersKey: @YES,
			wrapLinesKey: @NO,
			alwaysOnTopKey: @NO,
			languageKey: @"zh-Hans"
		}];
	}
	return self;
}

- (NSString *)fontName {
	NSString *fontName = [self.userDefaults stringForKey:fontNameKey];
	return fontName.length > 0 ? fontName : @"Menlo";
}

- (NSInteger)fontSize {
	return MIN(MAX([self.userDefaults integerForKey:fontSizeKey], 8), 36);
}

- (NSInteger)tabWidth {
	return MIN(MAX([self.userDefaults integerForKey:tabWidthKey], 1), 16);
}

- (BOOL)useTabs {
	return [self.userDefaults boolForKey:useTabsKey];
}

- (BOOL)showLineNumbers {
	return [self.userDefaults boolForKey:showLineNumbersKey];
}

- (BOOL)wrapLines {
	return [self.userDefaults boolForKey:wrapLinesKey];
}

- (BOOL)alwaysOnTop {
	return [self.userDefaults boolForKey:alwaysOnTopKey];
}

- (void)updateWrapLines:(BOOL)wrapLines {
	[self.userDefaults setBool:wrapLines forKey:wrapLinesKey];
	if (self.wrapLinesCheckbox) {
		self.wrapLinesCheckbox.state = wrapLines ? NSControlStateValueOn : NSControlStateValueOff;
	}
}

- (void)updateAlwaysOnTop:(BOOL)alwaysOnTop {
	[self.userDefaults setBool:alwaysOnTop forKey:alwaysOnTopKey];
}

- (NSString *)languageIdentifier {
	NSString *identifier = [self.userDefaults stringForKey:languageKey];
	return [[NppMacLocalization supportedLanguageIdentifiers] containsObject:identifier] ? identifier : @"zh-Hans";
}

- (void)showPreferences {
	if (!self.panel) {
		[self buildPanel];
	}
	[self syncControls];
	if (!self.panel.isVisible) {
		[self.panel center];
	}
	[self.panel makeKeyAndOrderFront:nil];
}

- (void)buildPanel {
	NSRect frame = NSMakeRect(0, 0, 430, 320);
	self.panel = [[NSPanel alloc] initWithContentRect:frame
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
		backing:NSBackingStoreBuffered
		defer:NO];
	self.panel.title = NppL("preferences.title");
	self.panel.floatingPanel = YES;
	self.panel.hidesOnDeactivate = NO;
	self.panel.releasedWhenClosed = NO;

	[self.panel.contentView addSubview:[self label:NppL("preferences.language") frame:NSMakeRect(24, 266, 96, 22)]];
	self.languagePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126, 262, 270, 28) pullsDown:NO];
	for (NSString *identifier in NppMacLocalization.supportedLanguageIdentifiers) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NppLocalizedString([@"language." stringByAppendingString:identifier])
			action:nil keyEquivalent:@""];
		item.representedObject = identifier;
		[self.languagePopup.menu addItem:item];
	}
	self.languagePopup.target = self;
	self.languagePopup.action = @selector(preferenceChanged:);
	[self.panel.contentView addSubview:self.languagePopup];

	[self.panel.contentView addSubview:[self label:NppL("preferences.font") frame:NSMakeRect(24, 220, 96, 22)]];
	self.fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126, 216, 270, 28) pullsDown:NO];
	NSArray<NSString *> *fonts = @[@"Menlo", @"Monaco", @"SF Mono", @"Courier New"];
	[self.fontPopup addItemsWithTitles:fonts];
	self.fontPopup.target = self;
	self.fontPopup.action = @selector(preferenceChanged:);
	[self.panel.contentView addSubview:self.fontPopup];

	[self.panel.contentView addSubview:[self label:NppL("preferences.fontSize") frame:NSMakeRect(24, 178, 96, 22)]];
	self.fontSizeField = [self numericFieldWithFrame:NSMakeRect(126, 175, 62, 26)];
	[self.panel.contentView addSubview:self.fontSizeField];
	self.fontSizeStepper = [self stepperWithFrame:NSMakeRect(190, 174, 22, 28) minimum:8 maximum:36];
	[self.panel.contentView addSubview:self.fontSizeStepper];

	[self.panel.contentView addSubview:[self label:NppL("preferences.tabWidth") frame:NSMakeRect(24, 136, 96, 22)]];
	self.tabWidthField = [self numericFieldWithFrame:NSMakeRect(126, 133, 62, 26)];
	[self.panel.contentView addSubview:self.tabWidthField];
	self.tabWidthStepper = [self stepperWithFrame:NSMakeRect(190, 132, 22, 28) minimum:1 maximum:16];
	[self.panel.contentView addSubview:self.tabWidthStepper];

	self.useTabsCheckbox = [self checkbox:NppL("preferences.useTabs") frame:NSMakeRect(126, 98, 220, 24)];
	[self.panel.contentView addSubview:self.useTabsCheckbox];
	self.lineNumbersCheckbox = [self checkbox:NppL("preferences.lineNumbers") frame:NSMakeRect(126, 66, 220, 24)];
	[self.panel.contentView addSubview:self.lineNumbersCheckbox];
	self.wrapLinesCheckbox = [self checkbox:NppL("preferences.wrapLines") frame:NSMakeRect(126, 34, 220, 24)];
	[self.panel.contentView addSubview:self.wrapLinesCheckbox];
}

- (NSTextField *)label:(NSString *)title frame:(NSRect)frame {
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	label.stringValue = title;
	label.bezeled = NO;
	label.drawsBackground = NO;
	label.editable = NO;
	label.selectable = NO;
	return label;
}

- (NSTextField *)numericFieldWithFrame:(NSRect)frame {
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
	field.alignment = NSTextAlignmentRight;
	field.target = self;
	field.action = @selector(preferenceChanged:);
	return field;
}

- (NSStepper *)stepperWithFrame:(NSRect)frame minimum:(double)minimum maximum:(double)maximum {
	NSStepper *stepper = [[NSStepper alloc] initWithFrame:frame];
	stepper.minValue = minimum;
	stepper.maxValue = maximum;
	stepper.increment = 1;
	stepper.target = self;
	stepper.action = @selector(stepperChanged:);
	return stepper;
}

- (NSButton *)checkbox:(NSString *)title frame:(NSRect)frame {
	NSButton *checkbox = [NSButton checkboxWithTitle:title target:self action:@selector(preferenceChanged:)];
	checkbox.frame = frame;
	return checkbox;
}

- (void)syncControls {
	for (NSMenuItem *item in self.languagePopup.itemArray) {
		if ([item.representedObject isEqual:self.languageIdentifier]) {
			[self.languagePopup selectItem:item];
			break;
		}
	}
	if (![self.fontPopup itemWithTitle:self.fontName]) {
		[self.fontPopup addItemWithTitle:self.fontName];
	}
	[self.fontPopup selectItemWithTitle:self.fontName];
	self.fontSizeField.integerValue = self.fontSize;
	self.fontSizeStepper.integerValue = self.fontSize;
	self.tabWidthField.integerValue = self.tabWidth;
	self.tabWidthStepper.integerValue = self.tabWidth;
	self.useTabsCheckbox.state = self.useTabs ? NSControlStateValueOn : NSControlStateValueOff;
	self.lineNumbersCheckbox.state = self.showLineNumbers ? NSControlStateValueOn : NSControlStateValueOff;
	self.wrapLinesCheckbox.state = self.wrapLines ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)stepperChanged:(NSStepper *)sender {
	if (sender == self.fontSizeStepper) {
		self.fontSizeField.integerValue = sender.integerValue;
	} else if (sender == self.tabWidthStepper) {
		self.tabWidthField.integerValue = sender.integerValue;
	}
	[self preferenceChanged:sender];
}

- (void)preferenceChanged:(id)sender {
	(void)sender;
	NSString *previousLanguage = self.languageIdentifier;
	NSString *selectedLanguage = self.languagePopup.selectedItem.representedObject ?: @"zh-Hans";
	NSInteger fontSize = MIN(MAX(self.fontSizeField.integerValue, 8), 36);
	NSInteger tabWidth = MIN(MAX(self.tabWidthField.integerValue, 1), 16);
	[self.userDefaults setObject:self.fontPopup.titleOfSelectedItem ?: @"Menlo" forKey:fontNameKey];
	[self.userDefaults setInteger:fontSize forKey:fontSizeKey];
	[self.userDefaults setInteger:tabWidth forKey:tabWidthKey];
	[self.userDefaults setBool:self.useTabsCheckbox.state == NSControlStateValueOn forKey:useTabsKey];
	[self.userDefaults setBool:self.lineNumbersCheckbox.state == NSControlStateValueOn forKey:showLineNumbersKey];
	[self.userDefaults setBool:self.wrapLinesCheckbox.state == NSControlStateValueOn forKey:wrapLinesKey];
	[self.userDefaults setObject:selectedLanguage forKey:languageKey];
	BOOL languageChanged = ![previousLanguage isEqualToString:selectedLanguage];
	if (languageChanged) {
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:selectedLanguage];
	}
	[self syncControls];
	if (self.changeHandler) {
		self.changeHandler();
	}
	if (languageChanged) {
		[self reloadLocalization];
	}
}

- (void)reloadLocalization {
	if (!self.panel) {
		return;
	}
	BOOL visible = self.panel.isVisible;
	NSPoint origin = self.panel.frame.origin;
	[self.panel orderOut:nil];
	self.panel = nil;
	if (visible) {
		[self buildPanel];
		[self syncControls];
		[self.panel setFrameOrigin:origin];
		[self.panel makeKeyAndOrderFront:nil];
	}
}

@end
