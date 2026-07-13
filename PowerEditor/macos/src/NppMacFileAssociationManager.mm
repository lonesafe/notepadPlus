#import "NppMacFileAssociationManager.h"

#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const selectedAssociationsKey = @"NppMacSelectedFileAssociations";
static NSString *const previousHandlersKey = @"NppMacPreviousFileAssociationHandlers";
static NSString *const associationErrorDomain = @"org.notepad-plus-plus.macos-port.file-association";

@implementation NppMacFileAssociationType
@end

@interface NppMacFileAssociationManager ()
@property(nonatomic, strong) NSUserDefaults *userDefaults;
@property(nonatomic, readwrite, copy) NSArray<NppMacFileAssociationType *> *supportedTypes;
@end

@implementation NppMacFileAssociationManager

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
	self = [super init];
	if (!self) return nil;
	_userDefaults = userDefaults;
	_supportedTypes = [self buildSupportedTypes];
	[_userDefaults registerDefaults:@{selectedAssociationsKey: @[], previousHandlersKey: @{}}];
	return self;
}

- (NppMacFileAssociationType *)type:(NSString *)identifier key:(NSString *)key extensions:(NSArray<NSString *> *)extensions {
	NppMacFileAssociationType *type = [[NppMacFileAssociationType alloc] init];
	type.identifier = identifier;
	type.localizationKey = key;
	type.extensions = extensions;
	return type;
}

- (NSArray<NppMacFileAssociationType *> *)buildSupportedTypes {
	return @[
		[self type:@"text" key:@"fileAssociation.type.text" extensions:@[@"txt", @"text", @"log"]],
		[self type:@"markdown" key:@"fileAssociation.type.markdown" extensions:@[@"md", @"markdown", @"mdown", @"mdx"]],
		[self type:@"web" key:@"fileAssociation.type.web" extensions:@[@"html", @"htm", @"xhtml", @"css", @"scss", @"less", @"xml"]],
		[self type:@"json" key:@"fileAssociation.type.json" extensions:@[@"json", @"jsonc", @"yaml", @"yml", @"toml"]],
		[self type:@"javascript" key:@"fileAssociation.type.javascript" extensions:@[@"js", @"jsx", @"mjs", @"cjs", @"ts", @"tsx"]],
		[self type:@"cpp" key:@"fileAssociation.type.cpp" extensions:@[@"c", @"h", @"cc", @"cpp", @"cxx", @"hpp", @"hxx"]],
		[self type:@"csharp" key:@"fileAssociation.type.csharp" extensions:@[@"cs"]],
		[self type:@"java" key:@"fileAssociation.type.java" extensions:@[@"java"]],
		[self type:@"python" key:@"fileAssociation.type.python" extensions:@[@"py", @"pyw"]],
		[self type:@"go" key:@"fileAssociation.type.go" extensions:@[@"go"]],
		[self type:@"shell" key:@"fileAssociation.type.shell" extensions:@[@"sh", @"bash", @"zsh", @"fish"]],
		[self type:@"swift" key:@"fileAssociation.type.swift" extensions:@[@"swift"]],
		[self type:@"sql" key:@"fileAssociation.type.sql" extensions:@[@"sql"]],
		[self type:@"config" key:@"fileAssociation.type.config" extensions:@[@"ini", @"cfg", @"conf", @"properties", @"env"]]
	];
}

- (NSSet<NSString *> *)selectedTypeIdentifiers {
	NSArray *stored = [self.userDefaults arrayForKey:selectedAssociationsKey] ?: @[];
	NSMutableSet<NSString *> *valid = [NSMutableSet set];
	NSSet *supported = [NSSet setWithArray:[self.supportedTypes valueForKey:@"identifier"]];
	for (id value in stored) {
		if ([value isKindOfClass:NSString.class] && [supported containsObject:value]) [valid addObject:value];
	}
	return valid;
}

- (NSDictionary<NSString *, NppMacFileAssociationType *> *)typesByExtension {
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	for (NppMacFileAssociationType *type in self.supportedTypes) {
		for (NSString *extension in type.extensions) types[extension] = type;
	}
	return types;
}

- (NSString *)legacyContentTypeForExtension:(NSString *)extension {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	CFStringRef value = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
		(__bridge CFStringRef)extension, kUTTypeData);
#pragma clang diagnostic pop
	return CFBridgingRelease(value);
}

- (void)applySelectedTypeIdentifiers:(NSSet<NSString *> *)identifiers
	completion:(void (^)(NSError *error))completion {
	NSSet *supported = [NSSet setWithArray:[self.supportedTypes valueForKey:@"identifier"]];
	NSMutableSet *selection = [identifiers mutableCopy] ?: [NSMutableSet set];
	[selection intersectSet:supported];
	NSSet *oldSelection = self.selectedTypeIdentifiers;
	NSMutableDictionary *previousHandlers = [[self.userDefaults dictionaryForKey:previousHandlersKey] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"org.notepad-plus-plus.macos-port";
	NSURL *applicationURL = NSBundle.mainBundle.bundleURL;
	NSMutableArray<NSError *> *errors = [NSMutableArray array];
	NSDictionary<NSString *, NppMacFileAssociationType *> *typesByExtension = [self typesByExtension];
	dispatch_group_t group = dispatch_group_create();

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	LSRegisterURL((__bridge CFURLRef)applicationURL, true);
#pragma clang diagnostic pop

	for (NSString *extension in typesByExtension) {
		NppMacFileAssociationType *typeDefinition = typesByExtension[extension];
		BOOL shouldAssociate = [selection containsObject:typeDefinition.identifier];
		BOOL wasAssociated = [oldSelection containsObject:typeDefinition.identifier];
		if (!shouldAssociate && !wasAssociated) continue;

		if (@available(macOS 12.0, *)) {
			UTType *contentType = [UTType typeWithFilenameExtension:extension conformingToType:UTTypeData];
			if (!contentType) continue;
			if (shouldAssociate && !previousHandlers[extension]) {
				NSURL *previousURL = [NSWorkspace.sharedWorkspace URLForApplicationToOpenContentType:contentType];
				if (previousURL && ![previousURL isEqual:applicationURL]) previousHandlers[extension] = previousURL.path;
			}
			NSURL *targetURL = shouldAssociate ? applicationURL : [NSURL fileURLWithPath:previousHandlers[extension] ?: @""];
			if (!targetURL.path.length) continue;
			dispatch_group_enter(group);
			[NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:targetURL toOpenContentType:contentType
				completionHandler:^(NSError *error) {
					@synchronized (errors) { if (error) [errors addObject:error]; }
					dispatch_group_leave(group);
				}];
		} else {
			NSString *contentType = [self legacyContentTypeForExtension:extension];
			if (!contentType.length) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			if (shouldAssociate && !previousHandlers[extension]) {
				NSString *previous = CFBridgingRelease(LSCopyDefaultRoleHandlerForContentType(
					(__bridge CFStringRef)contentType, kLSRolesEditor));
				if (previous.length && ![previous isEqualToString:bundleIdentifier]) previousHandlers[extension] = previous;
			}
			NSString *handler = shouldAssociate ? bundleIdentifier : previousHandlers[extension];
			if (handler.length) {
				OSStatus status = LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)contentType,
					kLSRolesEditor, (__bridge CFStringRef)handler);
				if (status != noErr) [errors addObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]];
			}
#pragma clang diagnostic pop
		}
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		[self.userDefaults setObject:previousHandlers forKey:previousHandlersKey];
		if (errors.count == 0) {
			[self.userDefaults setObject:selection.allObjects forKey:selectedAssociationsKey];
		}
		NSError *error = errors.firstObject;
		if (errors.count > 1) {
			error = [NSError errorWithDomain:associationErrorDomain code:1 userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%lu file association operations failed.",
					(unsigned long)errors.count]
			}];
		}
		if (completion) completion(error);
	});
}

@end
