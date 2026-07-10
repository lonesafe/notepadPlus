#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppMacCodeFormatter : NSObject

+ (nullable NSString *)languageIdentifierForURL:(nullable NSURL *)url languageName:(nullable NSString *)languageName;
+ (BOOL)supportsLanguageIdentifier:(nullable NSString *)languageIdentifier;
+ (nullable NSString *)formatText:(NSString *)text
	languageIdentifier:(NSString *)languageIdentifier
	fileURL:(nullable NSURL *)fileURL
	error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
