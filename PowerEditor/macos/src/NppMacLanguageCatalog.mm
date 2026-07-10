#import "NppMacLanguageCatalog.h"

@implementation NppMacLanguageDefinition
@end

@interface NppMacLanguageCatalog ()
@property(nonatomic, strong) NSDictionary<NSString *, NppMacLanguageDefinition *> *languagesByExtension;
@property(nonatomic, readwrite) NSArray<NppMacLanguageDefinition *> *allLanguages;
@end

@implementation NppMacLanguageCatalog

- (instancetype)initWithXMLURL:(NSURL *)url error:(NSError **)error {
	self = [super init];
	if (!self) {
		return nil;
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:error];
	if (!document) {
		return nil;
	}
	NSArray<NSXMLElement *> *languageElements = [document nodesForXPath:@"/NotepadPlus/Languages/Language" error:error];
	if (!languageElements) {
		return nil;
	}

	NSMutableDictionary<NSString *, NppMacLanguageDefinition *> *definitions = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NppMacLanguageDefinition *> *definitionsByName = [NSMutableDictionary dictionary];
	for (NSXMLElement *element in languageElements) {
		NSString *name = [[element attributeForName:@"name"] stringValue].lowercaseString;
		NSString *extensions = [[element attributeForName:@"ext"] stringValue];
		if (name.length == 0 || extensions.length == 0) {
			continue;
		}
		NppMacLanguageDefinition *definition = [[NppMacLanguageDefinition alloc] init];
		definition.name = name;
		definition.displayName = [self displayNameForLanguage:name];
		definition.lexerName = [self lexerNameForLanguage:name];
		definitionsByName[name] = definition;
		for (NSString *extension in [extensions componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
			if (extension.length > 0 && !definitions[extension.lowercaseString]) {
				definitions[extension.lowercaseString] = definition;
			}
		}
	}
	_languagesByExtension = definitions;
	_allLanguages = [definitionsByName.allValues sortedArrayUsingComparator:
		^NSComparisonResult(NppMacLanguageDefinition *left, NppMacLanguageDefinition *right) {
			return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
		}];
	return self;
}

- (NppMacLanguageDefinition *)languageForFileURL:(NSURL *)url {
	NSString *lastPath = url.lastPathComponent.lowercaseString;
	if ([lastPath isEqualToString:@"makefile"] || [lastPath isEqualToString:@"gnumakefile"]) {
		return [self definitionWithName:@"makefile"];
	}
	if ([lastPath isEqualToString:@"cmakelists.txt"]) {
		return [self definitionWithName:@"cmake"];
	}
	if ([lastPath isEqualToString:@"dockerfile"]) {
		return [self definitionWithName:@"bash"];
	}
	return self.languagesByExtension[url.pathExtension.lowercaseString];
}

- (NppMacLanguageDefinition *)definitionWithName:(NSString *)name {
	NppMacLanguageDefinition *definition = [[NppMacLanguageDefinition alloc] init];
	definition.name = name;
	definition.displayName = [self displayNameForLanguage:name];
	definition.lexerName = [self lexerNameForLanguage:name];
	return definition;
}

- (NSString *)lexerNameForLanguage:(NSString *)name {
	NSDictionary<NSString *, NSString *> *aliases = @{
		@"normal": @"",
		@"c": @"cpp", @"cpp": @"cpp", @"cs": @"cpp", @"java": @"cpp",
		@"javascript": @"cpp", @"javascript.js": @"cpp", @"go": @"cpp", @"rc": @"cpp",
		@"html": @"hypertext", @"asp": @"hypertext", @"jsp": @"hypertext", @"php": @"hypertext",
		@"ini": @"props", @"fortran77": @"f77", @"postscript": @"ps",
		@"baanc": @"baan", @"autoit": @"au3", @"json5": @"json",
		@"objective-c": @"objc"
	};
	return aliases[name] ?: name;
}

- (NSString *)displayNameForLanguage:(NSString *)name {
	NSDictionary<NSString *, NSString *> *names = @{
		@"cpp": @"C++", @"cs": @"C#", @"javascript.js": @"JavaScript",
		@"objc": @"Objective-C", @"html": @"HTML", @"json": @"JSON",
		@"json5": @"JSON5", @"sql": @"SQL", @"css": @"CSS",
		@"xml": @"XML", @"yaml": @"YAML", @"toml": @"TOML"
	};
	return names[name] ?: name.capitalizedString;
}

@end
