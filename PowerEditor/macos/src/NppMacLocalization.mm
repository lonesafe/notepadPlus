#import "NppMacLocalization.h"

NSString *const NppMacLanguageDidChangeNotification = @"NppMacLanguageDidChangeNotification";

@interface NppMacLocalization ()
@property(nonatomic, readwrite, copy) NSString *languageIdentifier;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *strings;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *englishFallback;
@end

@implementation NppMacLocalization

+ (instancetype)sharedLocalization {
	static NppMacLocalization *localization;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		localization = [[NppMacLocalization alloc] init];
	});
	return localization;
}

+ (NSArray<NSString *> *)supportedLanguageIdentifiers {
	return @[@"zh-Hans", @"en"];
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_englishFallback = [self stringsForLanguage:@"en"];
		_languageIdentifier = @"zh-Hans";
		_strings = [self stringsForLanguage:_languageIdentifier];
	}
	return self;
}

- (void)setLanguageIdentifier:(NSString *)languageIdentifier {
	NSString *resolved = [[self.class supportedLanguageIdentifiers] containsObject:languageIdentifier]
		? languageIdentifier : @"zh-Hans";
	if ([self.languageIdentifier isEqualToString:resolved] && self.strings.count > 0) {
		return;
	}
	_languageIdentifier = [resolved copy];
	self.strings = [self stringsForLanguage:resolved];
	[NSNotificationCenter.defaultCenter postNotificationName:NppMacLanguageDidChangeNotification object:self];
}

- (NSDictionary<NSString *, NSString *> *)stringsForLanguage:(NSString *)languageIdentifier {
	NSString *resourcePath = [NSBundle.mainBundle pathForResource:languageIdentifier ofType:@"lproj"];
	NSString *stringsPath = resourcePath.length > 0
		? [resourcePath stringByAppendingPathComponent:@"Localizable.strings"] : nil;
	NSDictionary *strings = stringsPath.length > 0 ? [NSDictionary dictionaryWithContentsOfFile:stringsPath] : nil;
	if (strings.count == 0) {
		NSString *developmentPath = [[NSFileManager.defaultManager currentDirectoryPath]
			stringByAppendingPathComponent:[NSString stringWithFormat:@"Resources/%@.lproj/Localizable.strings", languageIdentifier]];
		strings = [NSDictionary dictionaryWithContentsOfFile:developmentPath];
	}
	return strings ?: @{};
}

- (NSString *)stringForKey:(NSString *)key {
	return self.strings[key] ?: self.englishFallback[key] ?: key;
}

@end

NSString *NppLocalizedString(NSString *key) {
	return [[NppMacLocalization sharedLocalization] stringForKey:key];
}
