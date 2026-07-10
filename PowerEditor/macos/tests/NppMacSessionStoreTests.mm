#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacSessionStore.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

static NppMacSessionEntry *entry(NSString *path, NSInteger caret, NSInteger anchor,
	NSInteger firstLine, NSInteger xOffset) {
	NppMacSessionEntry *value = [[NppMacSessionEntry alloc] init];
	value.url = [NSURL fileURLWithPath:path];
	value.caretPosition = caret;
	value.anchorPosition = anchor;
	value.firstVisibleLine = firstLine;
	value.horizontalOffset = xOffset;
	return value;
}

int main() {
	@autoreleasepool {
		NSString *suiteName = [NSString stringWithFormat:@"org.notepad-plus-plus.session-tests.%@",
			NSUUID.UUID.UUIDString];
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
		NppMacSessionStore *store = [[NppMacSessionStore alloc] initWithUserDefaults:defaults];

		NSArray<NppMacSessionEntry *> *entries = @[
			entry(@"/tmp/first.cpp", 42, 37, 8, 12),
			entry(@"/tmp/second.md", 7, 7, 2, 0)
		];
		NppMacSessionEntry *recoveryEntry = entry(@"", 3, 1, 0, 0);
		recoveryEntry.url = nil;
		recoveryEntry.backupURL = [NSURL fileURLWithPath:@"/tmp/recovered.snapshot"];
		[store saveEntries:[entries arrayByAddingObject:recoveryEntry] activeIndex:2];
		NppMacSession *session = [store loadSession];
		require(session.entries.count == 3, "session should preserve file and recovery entries");
		require(session.activeIndex == 2, "session should preserve the active tab");
		require([session.entries[0].url.path isEqualToString:@"/tmp/first.cpp"], "session should preserve file paths");
		require(session.entries[0].caretPosition == 42, "session should preserve caret position");
		require(session.entries[0].anchorPosition == 37, "session should preserve selection anchor");
		require(session.entries[0].firstVisibleLine == 8, "session should preserve vertical scroll position");
		require(session.entries[0].horizontalOffset == 12, "session should preserve horizontal scroll position");
		require([session.entries[2].backupURL.path isEqualToString:@"/tmp/recovered.snapshot"],
			"session should preserve backup-only entries");

		[defaults setObject:@{
			@"version": @1,
			@"activeIndex": @99,
			@"documents": @[@{@"path": @"/tmp/clamped.txt", @"caret": @(-5)}]
		} forKey:@"NppMacOpenDocumentSession"];
		session = [store loadSession];
		require(session.activeIndex == 0, "active index should be clamped to available entries");
		require(session.entries[0].caretPosition == 0, "negative positions should be clamped to zero");

		[defaults removePersistentDomainForName:suiteName];
		std::puts("NppMacSessionStoreTests passed");
	}
	return 0;
}
