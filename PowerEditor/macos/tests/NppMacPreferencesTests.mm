#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacPreferencesController.h"
#import "NppMacLocalization.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"zh-Hans"];
		NSString *suiteName = [NSString stringWithFormat:@"org.notepad-plus-plus.preferences-tests.%@",
			NSUUID.UUID.UUIDString];
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
		NppMacPreferencesController *preferences =
			[[NppMacPreferencesController alloc] initWithUserDefaults:defaults];
		require([preferences.fontName isEqualToString:@"Menlo"], "default font should be Menlo");
		require(preferences.fontSize == 13, "default font size should be 13");
		require(preferences.tabWidth == 4, "default tab width should be 4");
		require(!preferences.useTabs && preferences.showLineNumbers && !preferences.wrapLines,
			"default editor switches should match the macOS port defaults");
		require([preferences.languageIdentifier isEqualToString:@"zh-Hans"],
			"interface language should default to Simplified Chinese");
		__block NSUInteger changeCount = 0;
		preferences.changeHandler = ^{ changeCount++; };
		[preferences showPreferences];
		NSPanel *preferencesPanel = [preferences valueForKey:@"panel"];
		require([preferencesPanel.title isEqualToString:@"偏好设置"], "preferences should initially render in Chinese");
		NSPopUpButton *languagePopup = [preferences valueForKey:@"languagePopup"];
		for (NSMenuItem *item in languagePopup.itemArray) {
			if ([item.representedObject isEqual:@"en"]) [languagePopup selectItem:item];
		}
		[preferences performSelector:@selector(preferenceChanged:) withObject:languagePopup];
		preferencesPanel = [preferences valueForKey:@"panel"];
		require([preferencesPanel.title isEqualToString:@"Preferences"],
			"changing language should immediately rebuild preferences in English");
		require(changeCount == 1 && [preferences.languageIdentifier isEqualToString:@"en"],
			"language selection should persist and notify the application");
		[preferencesPanel orderOut:nil];

		[defaults setObject:@"Monaco" forKey:@"NppMacEditorFontName"];
		[defaults setInteger:200 forKey:@"NppMacEditorFontSize"];
		[defaults setInteger:-2 forKey:@"NppMacEditorTabWidth"];
		[defaults setBool:YES forKey:@"NppMacEditorUseTabs"];
		[defaults setObject:@"en" forKey:@"NppMacInterfaceLanguage"];
		require([preferences.fontName isEqualToString:@"Monaco"], "stored font should be loaded");
		require(preferences.fontSize == 36, "font size should be clamped");
		require(preferences.tabWidth == 1, "tab width should be clamped");
		require(preferences.useTabs, "stored tab mode should be loaded");
		require([preferences.languageIdentifier isEqualToString:@"en"], "stored interface language should be loaded");

		[defaults removePersistentDomainForName:suiteName];
		std::puts("NppMacPreferencesTests passed");
	}
	return 0;
}
