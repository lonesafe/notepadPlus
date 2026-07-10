#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacRecoveryStore.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
		NppMacRecoveryStore *store = [[NppMacRecoveryStore alloc] initWithDirectoryURL:directory];
		NSError *error = nil;
		NSURL *snapshot = [store writeSnapshot:@"unsaved UTF-8 text" identifier:@"buffer-1" error:&error];
		require(snapshot != nil && error == nil, "snapshot should be written");
		NSString *text = [store readSnapshotAtURL:snapshot error:&error];
		require([text isEqualToString:@"unsaved UTF-8 text"], "snapshot should round-trip text");
		[store removeSnapshotAtURL:snapshot];
		require(![snapshot checkResourceIsReachableAndReturnError:nil], "snapshot should be removed");
		[[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
		std::puts("NppMacRecoveryStoreTests passed");
	}
	return 0;
}
