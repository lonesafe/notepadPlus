#import <Cocoa/Cocoa.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacFileAssociationController.h"
#import "NppMacFileAssociationManager.h"
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
		NSString *suiteName = [NSString stringWithFormat:@"org.notepad-plus-plus.file-association-tests.%@",
			NSUUID.UUID.UUIDString];
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
		NppMacFileAssociationManager *manager =
			[[NppMacFileAssociationManager alloc] initWithUserDefaults:defaults];

		require(manager.supportedTypes.count == 14, "all supported file type groups should be available");
		NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
		NSMutableSet<NSString *> *extensions = [NSMutableSet set];
		for (NppMacFileAssociationType *type in manager.supportedTypes) {
			require(type.identifier.length > 0 && type.localizationKey.length > 0 && type.extensions.count > 0,
				"each file type group should be complete");
			require(![identifiers containsObject:type.identifier], "file type identifiers should be unique");
			[identifiers addObject:type.identifier];
			for (NSString *extension in type.extensions) {
				require(![extensions containsObject:extension], "file extensions should not appear in multiple groups");
				[extensions addObject:extension];
			}
		}
		for (NSString *requiredExtension in @[@"md", @"json", @"js", @"html", @"java", @"c", @"cpp",
			@"cs", @"go", @"py"]) {
			require([extensions containsObject:requiredExtension], "requested programming extensions should be supported");
		}
		NSString *infoPlistPath = [NSFileManager.defaultManager.currentDirectoryPath
			stringByAppendingPathComponent:@"Resources/Info.plist"];
		NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
		NSArray *documentTypes = infoPlist[@"CFBundleDocumentTypes"];
		NSArray *declaredExtensions = [documentTypes.firstObject objectForKey:@"CFBundleTypeExtensions"];
		require([[NSSet setWithArray:declaredExtensions] isEqualToSet:extensions],
			"Info.plist extensions should match the file association configuration exactly");

		[defaults setObject:@[@"markdown", @"python", @"unsupported", @42]
			forKey:@"NppMacSelectedFileAssociations"];
		NSSet<NSString *> *storedSelection = manager.selectedTypeIdentifiers;
		require(storedSelection.count == 2 && [storedSelection containsObject:@"markdown"] &&
			[storedSelection containsObject:@"python"], "stored selection should ignore invalid values");

		NppMacFileAssociationController *controller =
			[[NppMacFileAssociationController alloc] initWithManager:manager];
		[controller showPanel];
		NSPanel *panel = [controller valueForKey:@"panel"];
		NSTableView *tableView = [controller valueForKey:@"tableView"];
		require([panel.title isEqualToString:@"文件关联"], "file association panel should default to Chinese");
		require(tableView.numberOfRows == 14 && tableView.tableColumns.count == 2,
			"file association table should show every group and both columns");

		[controller performSelector:@selector(selectAll:) withObject:nil];
		NSSet *selected = [controller valueForKey:@"selectedIdentifiers"];
		require(selected.count == manager.supportedTypes.count, "select all should select every file type group");
		[controller performSelector:@selector(clearSelection:) withObject:nil];
		require([[controller valueForKey:@"selectedIdentifiers"] count] == 0,
			"clear should deselect every file type group");

		NSString *snapshotPath = NSProcessInfo.processInfo.environment[@"NPP_FILE_ASSOCIATION_SNAPSHOT_PATH"];
		if (snapshotPath.length > 0) {
			panel.contentView.wantsLayer = YES;
			panel.contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
			[panel.contentView layoutSubtreeIfNeeded];
			NSBitmapImageRep *bitmap = [panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
			[panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
			NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
			require([png writeToFile:snapshotPath atomically:YES], "file association snapshot should be writable");
		}

		[NppMacLocalization.sharedLocalization setLanguageIdentifier:@"en"];
		[controller reloadLocalization];
		require([panel.title isEqualToString:@"File Associations"],
			"file association panel should update when the interface language changes");
		[panel orderOut:nil];
		[defaults removePersistentDomainForName:suiteName];
		std::puts("NppMacFileAssociationTests passed");
	}
	return 0;
}
