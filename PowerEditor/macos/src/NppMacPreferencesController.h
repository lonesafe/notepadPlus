#import <Cocoa/Cocoa.h>

@interface NppMacPreferencesController : NSObject

@property(nonatomic, readonly, copy) NSString *fontName;
@property(nonatomic, readonly) NSInteger fontSize;
@property(nonatomic, readonly) NSInteger tabWidth;
@property(nonatomic, readonly) BOOL useTabs;
@property(nonatomic, readonly) BOOL showLineNumbers;
@property(nonatomic, readonly) BOOL wrapLines;
@property(nonatomic, readonly) BOOL alwaysOnTop;
@property(nonatomic, readonly, copy) NSString *languageIdentifier;
@property(nonatomic, copy) void (^changeHandler)(void);

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (void)showPreferences;
- (void)showFileAssociations;
- (void)reloadLocalization;
- (void)updateWrapLines:(BOOL)wrapLines;
- (void)updateAlwaysOnTop:(BOOL)alwaysOnTop;

@end
