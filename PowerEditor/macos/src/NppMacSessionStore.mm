#import "NppMacSessionStore.h"

static NSString *const sessionDefaultsKey = @"NppMacOpenDocumentSession";

@implementation NppMacSessionEntry
@end

@implementation NppMacSession
@end

@interface NppMacSessionStore ()
@property(nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation NppMacSessionStore

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
	self = [super init];
	if (self) {
		_userDefaults = userDefaults;
	}
	return self;
}

- (NppMacSession *)loadSession {
	NppMacSession *session = [[NppMacSession alloc] init];
	session.entries = @[];
	session.activeIndex = 0;

	NSDictionary *payload = [self.userDefaults dictionaryForKey:sessionDefaultsKey];
	NSInteger version = [payload[@"version"] integerValue];
	if ((version != 1 && version != 2) || ![payload[@"documents"] isKindOfClass:NSArray.class]) {
		return session;
	}

	NSMutableArray<NppMacSessionEntry *> *entries = [NSMutableArray array];
	for (id value in payload[@"documents"]) {
		if (![value isKindOfClass:NSDictionary.class]) {
			continue;
		}
		NSDictionary *dictionary = value;
		NSString *path = [dictionary[@"path"] isKindOfClass:NSString.class] ? dictionary[@"path"] : nil;
		NSString *backupPath = [dictionary[@"backupPath"] isKindOfClass:NSString.class] ? dictionary[@"backupPath"] : nil;
		if (path.length == 0 && backupPath.length == 0) {
			continue;
		}

		NppMacSessionEntry *entry = [[NppMacSessionEntry alloc] init];
		entry.url = path.length > 0 ? [NSURL fileURLWithPath:path] : nil;
		entry.backupURL = backupPath.length > 0 ? [NSURL fileURLWithPath:backupPath] : nil;
		NSString *identifier = [dictionary[@"identifier"] isKindOfClass:NSString.class] ? dictionary[@"identifier"] : nil;
		entry.identifier = identifier.length > 0 ? identifier : NSUUID.UUID.UUIDString;
		entry.caretPosition = [self nonnegativeInteger:dictionary[@"caret"]];
		entry.anchorPosition = [self nonnegativeInteger:dictionary[@"anchor"]];
		entry.firstVisibleLine = [self nonnegativeInteger:dictionary[@"firstLine"]];
		entry.horizontalOffset = [self nonnegativeInteger:dictionary[@"xOffset"]];
		[entries addObject:entry];
	}

	session.entries = entries;
	NSInteger activeIndex = [self nonnegativeInteger:payload[@"activeIndex"]];
	if (entries.count > 0) {
		session.activeIndex = MIN(activeIndex, (NSInteger)entries.count - 1);
	}
	return session;
}

- (void)saveEntries:(NSArray<NppMacSessionEntry *> *)entries activeIndex:(NSInteger)activeIndex {
	NSMutableArray<NSDictionary *> *documents = [NSMutableArray arrayWithCapacity:entries.count];
	for (NppMacSessionEntry *entry in entries) {
		if ((!entry.url.isFileURL || entry.url.path.length == 0) &&
			(!entry.backupURL.isFileURL || entry.backupURL.path.length == 0)) {
			continue;
		}
		NSMutableDictionary *document = [@{
			@"identifier": entry.identifier.length > 0 ? entry.identifier : NSUUID.UUID.UUIDString,
			@"caret": @(MAX(entry.caretPosition, 0)),
			@"anchor": @(MAX(entry.anchorPosition, 0)),
			@"firstLine": @(MAX(entry.firstVisibleLine, 0)),
			@"xOffset": @(MAX(entry.horizontalOffset, 0))
		} mutableCopy];
		if (entry.url.path.length > 0) {
			document[@"path"] = entry.url.path;
		}
		if (entry.backupURL.path.length > 0) {
			document[@"backupPath"] = entry.backupURL.path;
		}
		[documents addObject:document];
	}

	NSInteger savedActiveIndex = documents.count == 0 ? 0 : MIN(MAX(activeIndex, 0), (NSInteger)documents.count - 1);
	[self.userDefaults setObject:@{
		@"version": @2,
		@"activeIndex": @(savedActiveIndex),
		@"documents": documents
	} forKey:sessionDefaultsKey];
}

- (NSInteger)nonnegativeInteger:(id)value {
	if (![value respondsToSelector:@selector(integerValue)]) {
		return 0;
	}
	return MAX([value integerValue], 0);
}

@end
