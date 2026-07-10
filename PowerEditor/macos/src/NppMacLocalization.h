#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const NppMacLanguageDidChangeNotification;
FOUNDATION_EXPORT NSString *NppLocalizedString(NSString *key);

@interface NppMacLocalization : NSObject
@property(nonatomic, readonly, copy) NSString *languageIdentifier;
+ (instancetype)sharedLocalization;
+ (NSArray<NSString *> *)supportedLanguageIdentifiers;
- (void)setLanguageIdentifier:(NSString *)languageIdentifier;
@end

#define NppL(key) NppLocalizedString(@key)
