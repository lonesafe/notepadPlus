#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacLocalization.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		NppMacLocalization *localization = NppMacLocalization.sharedLocalization;
		NSDictionary *chinese = [NSDictionary dictionaryWithContentsOfFile:
			@"Resources/zh-Hans.lproj/Localizable.strings"];
		NSDictionary *english = [NSDictionary dictionaryWithContentsOfFile:
			@"Resources/en.lproj/Localizable.strings"];
		require(chinese.count > 100 && [NSSet setWithArray:chinese.allKeys].count == [NSSet setWithArray:english.allKeys].count &&
			[[NSSet setWithArray:chinese.allKeys] isEqualToSet:[NSSet setWithArray:english.allKeys]],
			"every localization must provide the same complete key set");
		require([localization.languageIdentifier isEqualToString:@"zh-Hans"],
			"localization should default to Simplified Chinese");
		require([NppL("menu.file") isEqualToString:@"文件"], "Chinese menu resources should load");
		__block NSUInteger notifications = 0;
		id observer = [NSNotificationCenter.defaultCenter addObserverForName:NppMacLanguageDidChangeNotification
			object:localization queue:nil usingBlock:^(NSNotification *notification) {
				(void)notification;
				notifications++;
			}];
		[localization setLanguageIdentifier:@"en"];
		require([NppL("menu.file") isEqualToString:@"File"], "English resources should load at runtime");
		require(notifications == 1, "changing language should publish one refresh notification");
		[localization setLanguageIdentifier:@"unsupported"];
		require([localization.languageIdentifier isEqualToString:@"zh-Hans"],
			"unsupported languages should fall back to Simplified Chinese");
		[NSNotificationCenter.defaultCenter removeObserver:observer];
		std::puts("NppMacLocalizationTests passed");
	}
	return 0;
}
