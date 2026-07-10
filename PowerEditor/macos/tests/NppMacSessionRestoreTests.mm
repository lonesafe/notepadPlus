#import <Cocoa/Cocoa.h>
#import <objc/message.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacAppDelegate.h"
#import "NppMacFileDropView.h"
#import "NppMacRecoveryStore.h"
#import "NppMacSessionStore.h"
#import "NppMacLocalization.h"
#import "Scintilla.h"
#import "ScintillaView.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

static NppMacSessionEntry *entry(NSURL *url, NSInteger caret, NSInteger anchor) {
	NppMacSessionEntry *value = [[NppMacSessionEntry alloc] init];
	value.url = url;
	value.caretPosition = caret;
	value.anchorPosition = anchor;
	value.firstVisibleLine = 0;
	value.horizontalOffset = 0;
	return value;
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"zh-Hans"];
		NppMacAppDelegate *menuDelegate = [[NppMacAppDelegate alloc] init];
		[menuDelegate performSelector:@selector(buildMainMenu)];
		require([NSApp.mainMenu itemWithTitle:@"文件"] != nil, "main menu should default to Chinese");
		for (NSString *title in @[@"编辑", @"搜索", @"视图", @"编码", @"语言", @"设置", @"工具", @"宏", @"运行", @"插件", @"窗口", @"帮助"]) {
			require([NSApp.mainMenu itemWithTitle:title] != nil, "main menu should expose every original top-level menu");
		}
		NSMenu *fileMenu = [NSApp.mainMenu itemWithTitle:@"文件"].submenu;
		require([fileMenu itemWithTitle:@"全部保存"] != nil && [fileMenu itemWithTitle:@"关闭多个文档"].submenu != nil,
			"file menu should expose original save-all and close-multiple commands");
		NSMenu *editMenu = [NSApp.mainMenu itemWithTitle:@"编辑"].submenu;
		require([editMenu itemWithTitle:@"行操作"].submenu != nil && [editMenu itemWithTitle:@"换行符转换"].submenu != nil,
			"edit menu should expose original line and EOL operations");
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"en"];
		[menuDelegate performSelector:@selector(buildMainMenu)];
		require([NSApp.mainMenu itemWithTitle:@"File"] != nil, "main menu should rebuild in English");
		require([NSApp.mainMenu itemWithTitle:@"View"] != nil && [NSApp.mainMenu itemWithTitle:@"Encoding"] != nil &&
			[NSApp.mainMenu itemWithTitle:@"Help"] != nil, "all top-level menus should participate in runtime i18n");
		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"zh-Hans"];
		NSString *identifier = NSUUID.UUID.UUIDString;
		NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:identifier]
			isDirectory:YES];
		[[NSFileManager defaultManager] createDirectoryAtURL:directory
			withIntermediateDirectories:YES
			attributes:nil
			error:nil];
		NSURL *firstURL = [directory URLByAppendingPathComponent:@"first.cpp"];
		NSURL *secondURL = [directory URLByAppendingPathComponent:@"second.md"];
		[@"0123456789 first" writeToURL:firstURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[@"abcdefghij second" writeToURL:secondURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

		NSString *suiteName = [NSString stringWithFormat:@"org.notepad-plus-plus.restore-tests.%@", identifier];
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
		NppMacSessionStore *store = [[NppMacSessionStore alloc] initWithUserDefaults:defaults];
		NppMacRecoveryStore *recoveryStore = [[NppMacRecoveryStore alloc]
			initWithDirectoryURL:[directory URLByAppendingPathComponent:@"Backups" isDirectory:YES]];
		NSURL *backupURL = [recoveryStore writeSnapshot:@"recovered unsaved text"
			identifier:@"untitled-buffer"
			error:nil];
		NppMacSessionEntry *recoveredEntry = entry(nil, 10, 3);
		recoveredEntry.identifier = @"untitled-buffer";
		recoveredEntry.backupURL = backupURL;
		[store saveEntries:@[entry(firstURL, 6, 2), entry(secondURL, 9, 4), recoveredEntry] activeIndex:2];

		NppMacAppDelegate *delegate = [[NppMacAppDelegate alloc] init];
		[delegate performSelector:@selector(createEditorWindow)];
		[delegate setValue:store forKey:@"sessionStore"];
		[delegate setValue:recoveryStore forKey:@"recoveryStore"];
		[delegate setValue:[NSMutableDictionary dictionary] forKey:@"snapshotTimers"];
		[delegate performSelector:@selector(restoreSession)];

		NSArray *documents = [delegate valueForKey:@"documents"];
		require(documents.count == 3, "restore should open saved and recovered documents");
		require([[delegate valueForKey:@"currentDocumentIndex"] integerValue] == 2,
			"restore should select the recovered active tab");
		ScintillaView *editor = [delegate valueForKey:@"editor"];
		require([[editor string] isEqualToString:@"recovered unsaved text"], "active recovery tab should restore snapshot text");
		require([editor message:SCI_GETMODIFY] != 0, "recovered snapshot should remain marked as modified");
		[editor setString:@"beta\n\nalpha\nbeta\n"];
		[delegate performSelector:@selector(removeDuplicateLines:) withObject:nil];
		require([[editor string] isEqualToString:@"beta\n\nalpha"], "line operation commands should modify the active Scintilla document");
		[editor message:SCI_GOTOLINE wParam:0];
		[delegate performSelector:@selector(toggleBookmark:) withObject:nil];
		require(([editor message:SCI_MARKERGET wParam:0] & (1 << 24)) != 0, "bookmark command should set a Scintilla marker");
		[editor setString:@"{\"z\":1,\"a\":true}"];
		[delegate performSelector:@selector(formatDocumentWithLanguageIdentifier:) withObject:@"json"];
		require([[editor string] containsString:@"\n  \"a\""] && [[editor string] hasSuffix:@"\n"],
			"one-click formatter should replace the current editor document");
		[editor setString:@"recovered unsaved text"];
		NSURL *droppedURL = [directory URLByAppendingPathComponent:@"dropped.txt"];
		[@"opened from a window drop" writeToURL:droppedURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
		NppMacFileDropView *dropView = [[NppMacFileDropView alloc] initWithFrame:NSZeroRect];
		[(id<NppMacFileDropViewDelegate>)delegate fileDropView:dropView openFileURLs:@[droppedURL]];
		require([[editor string] isEqualToString:@"opened from a window drop"],
			"dropping a file into the editor window should open it as the active document");

		using SwitchDocumentFn = void (*)(id, SEL, NSUInteger);
		reinterpret_cast<SwitchDocumentFn>(objc_msgSend)(delegate, @selector(switchToDocumentAtIndex:), 0);
		require([[editor string] isEqualToString:@"0123456789 first"], "switching tabs should restore the target document");
	require([editor message:SCI_GETCURRENTPOS] == 6 && [editor message:SCI_GETANCHOR] == 2,
			"switching tabs should restore the target selection");
		[@"updated on disk" writeToURL:firstURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
		using ReloadDocumentFn = BOOL (*)(id, SEL);
		BOOL reloaded = reinterpret_cast<ReloadDocumentFn>(objc_msgSend)(delegate,
			@selector(reloadCurrentDocumentFromDisk));
		require(reloaded, "reload should succeed for an existing file");
		require([[editor string] isEqualToString:@"updated on disk"], "reload should read the latest disk content");
		require([editor message:SCI_GETMODIFY] == 0, "reload should reset the document save point");

		[editor setString:@"content captured before a crash"];
		id currentDocument = [delegate performSelector:@selector(currentDocument)];
		using SnapshotDocumentFn = void (*)(id, SEL, id);
		reinterpret_cast<SnapshotDocumentFn>(objc_msgSend)(delegate, @selector(snapshotDocument:), currentDocument);
		NppMacSession *snapshotSession = [store loadSession];
		require(snapshotSession.entries.count > 0 && snapshotSession.entries[0].backupURL != nil,
			"snapshot should persist a recovery entry in the session");

		NppMacAppDelegate *restoredDelegate = [[NppMacAppDelegate alloc] init];
		[restoredDelegate performSelector:@selector(createEditorWindow)];
		[restoredDelegate setValue:store forKey:@"sessionStore"];
		[restoredDelegate setValue:recoveryStore forKey:@"recoveryStore"];
		[restoredDelegate setValue:[NSMutableDictionary dictionary] forKey:@"snapshotTimers"];
		[restoredDelegate performSelector:@selector(restoreSession)];
		ScintillaView *restoredEditor = [restoredDelegate valueForKey:@"editor"];
		require([[restoredEditor string] isEqualToString:@"content captured before a crash"],
			"a new app instance should restore the latest crash snapshot");
		require([restoredEditor message:SCI_GETMODIFY] != 0,
			"crash-restored content should remain modified");

		NSWindow *window = [delegate valueForKey:@"window"];
		[window orderOut:nil];
		NSWindow *restoredWindow = [restoredDelegate valueForKey:@"window"];
		[restoredWindow orderOut:nil];
		[defaults removePersistentDomainForName:suiteName];
		[[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
		std::puts("NppMacSessionRestoreTests passed");
	}
	return 0;
}
