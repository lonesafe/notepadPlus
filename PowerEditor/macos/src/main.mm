#import <Cocoa/Cocoa.h>

#import "NppMacAppDelegate.h"

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		NppMacAppDelegate *delegate = [[NppMacAppDelegate alloc] init];
		app.delegate = delegate;
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		for (int index = 1; index < argc; ++index) {
			NSString *argument = [NSString stringWithUTF8String:argv[index]];
			if (argument.length == 0 || [argument hasPrefix:@"-"]) continue;
			NSString *path = argument.stringByExpandingTildeInPath;
			if (![path isAbsolutePath]) path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
			BOOL isDirectory = NO;
			if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
				[delegate application:app openFile:path.stringByStandardizingPath];
			}
		}
		[app run];
	}
	return 0;
}
