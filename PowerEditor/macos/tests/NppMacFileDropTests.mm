#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacFileDropView.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
		NSURL *directoryURL = [NSURL fileURLWithPath:temporaryPath isDirectory:YES];
		[NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
		NSURL *firstURL = [directoryURL URLByAppendingPathComponent:@"first.txt"];
		NSURL *secondURL = [directoryURL URLByAppendingPathComponent:@"source.unknown-extension"];
		[@"first" writeToURL:firstURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[@"second" writeToURL:secondURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

		NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
		[pasteboard clearContents];
		[pasteboard writeObjects:@[firstURL, directoryURL, secondURL]];
		NSArray<NSURL *> *fileURLs = [NppMacFileDropView fileURLsFromPasteboard:pasteboard];
		require(fileURLs.count == 2, "file drops should accept files and reject directories");
		require([fileURLs containsObject:firstURL.URLByStandardizingPath] &&
			[fileURLs containsObject:secondURL.URLByStandardizingPath],
			"file drops should preserve every supported file URL regardless of extension");

		[NSFileManager.defaultManager removeItemAtURL:directoryURL error:nil];
		std::puts("NppMacFileDropTests passed");
	}
	return 0;
}
