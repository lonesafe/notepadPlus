#import "NppMacAppDelegate.h"
#import "NppMacCodeFormatter.h"
#import "NppMacFileDropView.h"
#import "NppMacFindPanelController.h"
#import "NppMacLanguageCatalog.h"
#import "NppMacLocalization.h"
#import "NppMacMarkdownPreviewController.h"
#import "NppMacPreferencesController.h"
#import "NppMacRecoveryStore.h"
#import "NppMacSessionStore.h"
#import "NppMacTabBarView.h"
#import "NppMacToolBarView.h"

#import <CommonCrypto/CommonDigest.h>
#include <cstdint>
#include <dlfcn.h>

#import "ILexer.h"
#import "Scintilla.h"
#import "ScintillaView.h"
#import "SciLexer.h"
#import "Lexilla.h"

static const char cppKeywords[] =
	"alignas alignof and and_eq asm atomic_cancel atomic_commit atomic_noexcept auto bitand bitor bool break "
	"case catch char char8_t char16_t char32_t class compl concept const consteval constexpr constinit const_cast "
	"continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export "
	"extern false float for friend goto if inline int long mutable namespace new noexcept not not_eq nullptr operator "
	"or or_eq private protected public reflexpr register reinterpret_cast requires return short signed sizeof static "
	"static_assert static_cast struct switch synchronized template this thread_local throw true try typedef typeid "
	"typename union unsigned using virtual void volatile wchar_t while xor xor_eq";

static const char cppTypeKeywords[] =
	"std string vector map unordered_map set unordered_set optional variant unique_ptr shared_ptr weak_ptr size_t "
	"uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t";

static const char pythonKeywords[] =
	"False None True and as assert async await break class continue def del elif else except finally for from global "
	"if import in is lambda nonlocal not or pass raise return try while with yield match case";

static const char jsonKeywords[] = "false true null";

static const char bashKeywords[] =
	"alias bg bind break builtin caller case cd command compgen complete continue declare dirs disown do done echo "
	"elif else enable esac eval exec exit export false fc fg fi for function getopts hash help history if in jobs "
	"kill let local logout popd printf pushd pwd read readonly return select set shift shopt source suspend test "
	"then time times trap true type typeset ulimit umask unalias unset until wait while";

@interface NppMacDocument : NSObject
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, copy) NSString *languageName;
@property(nonatomic) sptr_t documentPointer;
@property(nonatomic) BOOL dirty;
@property(nonatomic) NSInteger caretPosition;
@property(nonatomic) NSInteger anchorPosition;
@property(nonatomic) NSInteger firstVisibleLine;
@property(nonatomic) NSInteger horizontalOffset;
@property(nonatomic, strong) NSDate *lastKnownModificationDate;
@property(nonatomic) BOOL missingOnDisk;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, strong) NSURL *backupURL;
@property(nonatomic) BOOL discardOnTermination;
@property(nonatomic) NSStringEncoding encoding;
@property(nonatomic) BOOL writeBOM;
@end

@implementation NppMacDocument
@end

@interface NppMacMacroStep : NSObject
@property(nonatomic) int message;
@property(nonatomic) uptr_t wParam;
@property(nonatomic) sptr_t lParam;
@property(nonatomic, copy) NSString *text;
@end

@implementation NppMacMacroStep
@end

@interface NppMacAppDelegate () <ScintillaNotificationProtocol, NppMacTabBarViewDelegate, NppMacFileDropViewDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) ScintillaView *editor;
@property(nonatomic, strong) NppMacFindPanelController *findPanelController;
@property(nonatomic, strong) NppMacMarkdownPreviewController *markdownPreviewController;
@property(nonatomic, strong) NppMacLanguageCatalog *languageCatalog;
@property(nonatomic, strong) NppMacPreferencesController *preferencesController;
@property(nonatomic, strong) NppMacToolBarView *toolBar;
@property(nonatomic, strong) NppMacTabBarView *tabBar;
@property(nonatomic, strong) NSTextField *statusBar;
@property(nonatomic, strong) NSMutableArray<NppMacDocument *> *documents;
@property(nonatomic, strong) NSMutableArray<NSURL *> *pendingDocumentURLs;
@property(nonatomic, strong) NppMacSessionStore *sessionStore;
@property(nonatomic, strong) NppMacRecoveryStore *recoveryStore;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTimer *> *snapshotTimers;
@property(nonatomic) NSInteger currentDocumentIndex;
@property(nonatomic) void *lexillaHandle;
@property(nonatomic) BOOL suppressDirtyTracking;
@property(nonatomic) BOOL terminationConfirmedByWindowClose;
@property(nonatomic) BOOL restoringSession;
@property(nonatomic) BOOL checkingExternalChanges;
@property(nonatomic) BOOL confirmingAllDocuments;
@property(nonatomic, strong) NSMutableArray<NppMacMacroStep *> *recordedMacro;
@property(nonatomic) BOOL recordingMacro;
- (NppMacDocument *)currentDocument;
- (void)appendDocumentWithText:(NSString *)text url:(NSURL *)url;
- (void)switchToDocumentAtIndex:(NSUInteger)index;
- (BOOL)writeCurrentDocumentToURL:(NSURL *)url;
- (BOOL)saveCurrentDocumentAs;
- (BOOL)closeDocumentAtIndex:(NSUInteger)index;
- (BOOL)confirmCloseDocumentAtIndex:(NSUInteger)index;
- (BOOL)confirmCloseAllDocuments;
- (void)captureCurrentDocumentViewState;
- (void)restoreCurrentDocumentViewState;
- (void)persistSession;
- (void)restoreSession;
- (void)applyEditorPreferences;
- (BOOL)reloadCurrentDocumentFromDisk;
- (void)checkForExternalFileChanges;
- (NSDate *)modificationDateForURL:(NSURL *)url;
- (void)scheduleSnapshotForDocument:(NppMacDocument *)document;
- (void)snapshotDocument:(NppMacDocument *)document;
- (void)removeSnapshotForDocument:(NppMacDocument *)document;
- (NSArray<NppMacFindDocumentSnapshot *> *)findDocumentSnapshots;
- (void)replaceDocumentAtIndex:(NSUInteger)index withText:(NSString *)text;
- (void)updateToolBar;
- (NSMenu *)addSubmenu:(NSString *)title toMenu:(NSMenu *)menu;
- (NSMenuItem *)addDisabledItem:(NSString *)title toMenu:(NSMenu *)menu;
@end

@implementation NppMacAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	(void)notification;
	[self loadLexilla];
	NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"AppIcon" withExtension:@"icns"];
	if (iconURL) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfURL:iconURL];
	NSURL *languageXML = [NSBundle.mainBundle URLForResource:@"langs.model" withExtension:@"xml"];
	self.languageCatalog = [[NppMacLanguageCatalog alloc] initWithXMLURL:languageXML error:nil];
	NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
	self.sessionStore = [[NppMacSessionStore alloc] initWithUserDefaults:userDefaults];
	NSURL *applicationSupport = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
		inDomains:NSUserDomainMask].firstObject;
	NSURL *backupDirectory = [[applicationSupport URLByAppendingPathComponent:@"Notepad++Mac" isDirectory:YES]
		URLByAppendingPathComponent:@"Backups" isDirectory:YES];
	self.recoveryStore = [[NppMacRecoveryStore alloc] initWithDirectoryURL:backupDirectory];
	self.snapshotTimers = [NSMutableDictionary dictionary];
	self.preferencesController = [[NppMacPreferencesController alloc] initWithUserDefaults:userDefaults];
	[NppMacLocalization.sharedLocalization setLanguageIdentifier:self.preferencesController.languageIdentifier];
	__weak NppMacAppDelegate *weakSelf = self;
	self.preferencesController.changeHandler = ^{
		[weakSelf applyEditorPreferences];
		[weakSelf applyLexerForURL:weakSelf.currentDocument.url];
		[weakSelf buildMainMenu];
		[weakSelf.findPanelController reloadLocalization];
		[weakSelf.toolBar reloadLocalization];
		[weakSelf rebuildTabBar];
		[weakSelf updateWindowTitle];
	};
	[self buildMainMenu];
	[self createEditorWindow];
	if (self.pendingDocumentURLs.count > 0) {
		for (NSURL *url in self.pendingDocumentURLs.copy) {
			[self openURL:url];
		}
	} else {
		[self restoreSession];
	}
	[self.pendingDocumentURLs removeAllObjects];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)dealloc {
	for (NSTimer *timer in self.snapshotTimers.allValues) {
		[timer invalidate];
	}
	for (NppMacDocument *document in self.documents) {
		if (document.documentPointer) {
			[self.editor message:SCI_RELEASEDOCUMENT wParam:0 lParam:document.documentPointer];
		}
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	(void)sender;
	return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	(void)notification;
	[self checkForExternalFileChanges];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
	(void)sender;
	NSURL *url = [NSURL fileURLWithPath:filename];
	if (!self.editor) {
		if (!self.pendingDocumentURLs) {
			self.pendingDocumentURLs = [NSMutableArray array];
		}
		[self.pendingDocumentURLs addObject:url];
		return YES;
	}
	return [self openURL:url];
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
	BOOL openedAll = YES;
	for (NSString *filename in filenames) {
		NSURL *url = [NSURL fileURLWithPath:filename];
		if (!self.editor) {
			if (!self.pendingDocumentURLs) {
				self.pendingDocumentURLs = [NSMutableArray array];
			}
			[self.pendingDocumentURLs addObject:url];
		} else {
			openedAll = [self openURL:url] && openedAll;
		}
	}
	[sender replyToOpenOrPrint:openedAll ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	(void)sender;
	if (self.terminationConfirmedByWindowClose) {
		return NSTerminateNow;
	}
	if (![self confirmCloseAllDocuments]) {
		return NSTerminateCancel;
	}
	[self persistSession];
	return NSTerminateNow;
}

- (BOOL)windowShouldClose:(id)sender {
	(void)sender;
	BOOL approved = [self confirmCloseAllDocuments];
	if (approved) {
		[self persistSession];
	}
	self.terminationConfirmedByWindowClose = approved;
	return approved;
}

- (void)notification:(SCNotification *)notification {
	if (notification->nmhdr.code == SCN_MACRORECORD && self.recordingMacro) {
		NppMacMacroStep *step = [[NppMacMacroStep alloc] init];
		step.message = notification->message;
		step.wParam = notification->wParam;
		step.lParam = notification->lParam;
		if ((step.message == SCI_REPLACESEL || step.message == SCI_ADDTEXT || step.message == SCI_INSERTTEXT) &&
			notification->lParam) {
			step.text = [NSString stringWithUTF8String:reinterpret_cast<const char *>(notification->lParam)] ?: @"";
		}
		[self.recordedMacro addObject:step];
	}
	if (notification->nmhdr.code == SCN_UPDATEUI) {
		[self updateStatusBar];
	}
	if (!self.suppressDirtyTracking &&
		(notification->nmhdr.code == SCN_MODIFIED ||
		 notification->nmhdr.code == SCN_SAVEPOINTLEFT ||
		 notification->nmhdr.code == SCN_SAVEPOINTREACHED)) {
		[self updateDirtyState];
		if (notification->nmhdr.code == SCN_MODIFIED && self.currentDocument.dirty) {
			[self scheduleSnapshotForDocument:self.currentDocument];
			[self updateMarkdownPreview];
		}
	}
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
	SEL action = item.action;
	if (action == @selector(reloadDocument:)) {
		return self.currentDocument.url != nil;
	}
	if (action == @selector(toggleMarkdownPreview:)) {
		return [self isCurrentDocumentMarkdown];
	}
	if (action == @selector(formatCurrentDocument:)) {
		NSString *language = [NppMacCodeFormatter languageIdentifierForURL:self.currentDocument.url
			languageName:self.currentDocument.languageName];
		return [NppMacCodeFormatter supportsLanguageIdentifier:language];
	}
	if (action == @selector(saveDocument:) ||
		action == @selector(saveDocumentAs:) ||
		action == @selector(closeDocument:) ||
		action == @selector(findText:) ||
		action == @selector(findNextText:) ||
		action == @selector(findPreviousText:) ||
		action == @selector(replaceText:)) {
		return self.currentDocument != nil;
	}
	if (action == @selector(undo:)) {
		return self.editor && [self.editor message:SCI_CANUNDO] != 0;
	}
	if (action == @selector(redo:)) {
		return self.editor && [self.editor message:SCI_CANREDO] != 0;
	}
	return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
	SEL action = item.action;
	if (action == @selector(toggleAlwaysOnTop:)) item.state = self.window.level == NSFloatingWindowLevel ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleMarkdownPreview:)) item.state = self.markdownPreviewController.previewVisible ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleWhitespace:)) item.state = [self.editor message:SCI_GETVIEWWS] != SCWS_INVISIBLE ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleEOLVisibility:)) item.state = [self.editor message:SCI_GETVIEWEOL] ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleIndentGuides:)) item.state = [self.editor message:SCI_GETINDENTATIONGUIDES] != SC_IV_NONE ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleWordWrap:)) item.state = [self.editor message:SCI_GETWRAPMODE] != SC_WRAP_NONE ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(toggleReadOnly:)) item.state = [self.editor message:SCI_GETREADONLY] ? NSControlStateValueOn : NSControlStateValueOff;
	else if (action == @selector(selectEncoding:)) {
		NSDictionary *choice = item.representedObject;
		item.state = self.currentDocument.encoding == [choice[@"encoding"] unsignedIntegerValue] &&
			self.currentDocument.writeBOM == [choice[@"bom"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
	}
	else if (action == @selector(selectLanguage:)) {
		NppMacLanguageDefinition *definition = item.representedObject;
		item.state = definition && ([self.currentDocument.languageName caseInsensitiveCompare:definition.displayName] == NSOrderedSame ||
			([definition.name isEqualToString:@"normal"] && [self.currentDocument.languageName isEqualToString:NppL("status.plainText")])) ?
			NSControlStateValueOn : NSControlStateValueOff;
	}
	return [self validateUserInterfaceItem:item];
}

- (void)buildMainMenu {
	NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
	NSApp.mainMenu = mainMenu;

	NSMenuItem *appItem = [mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Notepad++Mac"];
	appItem.submenu = appMenu;
	[appMenu addItemWithTitle:NppL("menu.app.about") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""].target = NSApp;
	[appMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.app.preferences") action:@selector(showPreferences:) key:@"," toMenu:appMenu];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:NppL("menu.app.quit") action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;

	NSMenu *fileMenu = [self addSubmenu:NppL("menu.file") toMenu:mainMenu];
	[self addItem:NppL("menu.file.new") action:@selector(newDocument:) key:@"n" toMenu:fileMenu];
	[self addItem:NppL("menu.file.open") action:@selector(openDocument:) key:@"o" toMenu:fileMenu];
	NSMenu *containingMenu = [self addSubmenu:NppL("menu.file.openContaining") toMenu:fileMenu];
	[self addItem:NppL("menu.file.finder") action:@selector(openContainingFolder:) key:@"" toMenu:containingMenu];
	[self addItem:NppL("menu.file.terminal") action:@selector(openContainingFolderInTerminal:) key:@"" toMenu:containingMenu];
	[self addDisabledItem:NppL("menu.file.folderWorkspace") toMenu:containingMenu];
	[self addItem:NppL("menu.file.defaultViewer") action:@selector(openInDefaultViewer:) key:@"" toMenu:fileMenu];
	[self addDisabledItem:NppL("menu.file.openFolderWorkspace") toMenu:fileMenu];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.file.reload") action:@selector(reloadDocument:) key:@"R" toMenu:fileMenu].keyEquivalentModifierMask =
		NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[self addItem:NppL("menu.file.save") action:@selector(saveDocument:) key:@"s" toMenu:fileMenu];
	NSMenuItem *saveAs = [self addItem:NppL("menu.file.saveAs") action:@selector(saveDocumentAs:) key:@"S" toMenu:fileMenu];
	saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[self addItem:NppL("menu.file.saveCopy") action:@selector(saveCopyAs:) key:@"" toMenu:fileMenu];
	[self addItem:NppL("menu.file.saveAll") action:@selector(saveAllDocuments:) key:@"" toMenu:fileMenu];
	[self addItem:NppL("menu.file.rename") action:@selector(renameDocument:) key:@"" toMenu:fileMenu];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.file.closeTab") action:@selector(closeDocument:) key:@"w" toMenu:fileMenu];
	[self addItem:NppL("menu.file.closeAll") action:@selector(closeAllDocuments:) key:@"" toMenu:fileMenu];
	NSMenu *closeMultiple = [self addSubmenu:NppL("menu.file.closeMultiple") toMenu:fileMenu];
	[self addItem:NppL("menu.file.closeOthers") action:@selector(closeOtherDocuments:) key:@"" toMenu:closeMultiple];
	[self addItem:NppL("menu.file.closeLeft") action:@selector(closeDocumentsToLeft:) key:@"" toMenu:closeMultiple];
	[self addItem:NppL("menu.file.closeRight") action:@selector(closeDocumentsToRight:) key:@"" toMenu:closeMultiple];
	[self addItem:NppL("menu.file.closeUnchanged") action:@selector(closeUnchangedDocuments:) key:@"" toMenu:closeMultiple];
	[self addItem:NppL("menu.file.trash") action:@selector(moveDocumentToTrash:) key:@"" toMenu:fileMenu];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[self addDisabledItem:NppL("menu.file.loadSession") toMenu:fileMenu];
	[self addDisabledItem:NppL("menu.file.saveSession") toMenu:fileMenu];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.file.print") action:@selector(printDocument:) key:@"p" toMenu:fileMenu];
	[self addItem:NppL("menu.file.printNow") action:@selector(printDocumentNow:) key:@"" toMenu:fileMenu];

	NSMenu *editMenu = [self addSubmenu:NppL("menu.edit") toMenu:mainMenu];
	[self addItem:NppL("menu.edit.undo") action:@selector(undo:) key:@"z" toMenu:editMenu];
	[self addItem:NppL("menu.edit.redo") action:@selector(redo:) key:@"Z" toMenu:editMenu].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[editMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.edit.cut") action:@selector(cut:) key:@"x" toMenu:editMenu];
	[self addItem:NppL("menu.edit.copy") action:@selector(copy:) key:@"c" toMenu:editMenu];
	[self addItem:NppL("menu.edit.paste") action:@selector(paste:) key:@"v" toMenu:editMenu];
	[self addItem:NppL("menu.edit.delete") action:@selector(deleteSelection:) key:@"" toMenu:editMenu];
	[self addItem:NppL("menu.edit.selectAll") action:@selector(selectAll:) key:@"a" toMenu:editMenu];
	[editMenu addItem:[NSMenuItem separatorItem]];
	NSMenu *insertMenu = [self addSubmenu:NppL("menu.edit.insert") toMenu:editMenu];
	[self addItem:NppL("menu.edit.dateShort") action:@selector(insertShortDateTime:) key:@"" toMenu:insertMenu];
	[self addItem:NppL("menu.edit.dateLong") action:@selector(insertLongDateTime:) key:@"" toMenu:insertMenu];
	NSMenu *copyPathMenu = [self addSubmenu:NppL("menu.edit.copyClipboard") toMenu:editMenu];
	[self addItem:NppL("menu.edit.copyFullPath") action:@selector(copyFullPath:) key:@"" toMenu:copyPathMenu];
	[self addItem:NppL("menu.edit.copyFilename") action:@selector(copyFilename:) key:@"" toMenu:copyPathMenu];
	[self addItem:NppL("menu.edit.copyDirectory") action:@selector(copyDirectory:) key:@"" toMenu:copyPathMenu];
	[copyPathMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.edit.copyAllNames") action:@selector(copyAllFilenames:) key:@"" toMenu:copyPathMenu];
	[self addItem:NppL("menu.edit.copyAllPaths") action:@selector(copyAllFilePaths:) key:@"" toMenu:copyPathMenu];
	NSMenu *indentMenu = [self addSubmenu:NppL("menu.edit.indent") toMenu:editMenu];
	[self addItem:NppL("menu.edit.indentIncrease") action:@selector(increaseIndent:) key:@"]" toMenu:indentMenu];
	[self addItem:NppL("menu.edit.indentDecrease") action:@selector(decreaseIndent:) key:@"[" toMenu:indentMenu];
	NSMenu *caseMenu = [self addSubmenu:NppL("menu.edit.case") toMenu:editMenu];
	[self addItem:NppL("menu.edit.uppercase") action:@selector(uppercaseSelection:) key:@"" toMenu:caseMenu];
	[self addItem:NppL("menu.edit.lowercase") action:@selector(lowercaseSelection:) key:@"" toMenu:caseMenu];
	[self addItem:NppL("menu.edit.titlecase") action:@selector(titlecaseSelection:) key:@"" toMenu:caseMenu];
	[self addItem:NppL("menu.edit.invertcase") action:@selector(invertCaseSelection:) key:@"" toMenu:caseMenu];
	NSMenu *lineMenu = [self addSubmenu:NppL("menu.edit.lineOperations") toMenu:editMenu];
	[self addItem:NppL("menu.edit.duplicateLine") action:@selector(duplicateLine:) key:@"d" toMenu:lineMenu].keyEquivalentModifierMask = NSEventModifierFlagCommand;
	[self addItem:NppL("menu.edit.removeDuplicates") action:@selector(removeDuplicateLines:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.splitLines") action:@selector(splitLines:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.joinLines") action:@selector(joinLines:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.moveLineUp") action:@selector(moveLineUp:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.moveLineDown") action:@selector(moveLineDown:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.removeEmpty") action:@selector(removeEmptyLines:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.removeBlank") action:@selector(removeBlankLines:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.blankAbove") action:@selector(insertBlankLineAbove:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.blankBelow") action:@selector(insertBlankLineBelow:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.reverseLines") action:@selector(reverseLines:) key:@"" toMenu:lineMenu];
	[lineMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.edit.sortAsc") action:@selector(sortLinesAscending:) key:@"" toMenu:lineMenu];
	[self addItem:NppL("menu.edit.sortDesc") action:@selector(sortLinesDescending:) key:@"" toMenu:lineMenu];
	NSMenu *commentMenu = [self addSubmenu:NppL("menu.edit.comment") toMenu:editMenu];
	[self addItem:NppL("menu.edit.toggleComment") action:@selector(toggleLineComment:) key:@"/" toMenu:commentMenu];
	[self addItem:NppL("menu.edit.commentSet") action:@selector(commentLines:) key:@"" toMenu:commentMenu];
	[self addItem:NppL("menu.edit.commentRemove") action:@selector(uncommentLines:) key:@"" toMenu:commentMenu];
	NSMenu *eolMenu = [self addSubmenu:NppL("menu.edit.eol") toMenu:editMenu];
	[self addEOLItem:NppL("menu.edit.eolWindows") mode:SC_EOL_CRLF toMenu:eolMenu];
	[self addEOLItem:NppL("menu.edit.eolUnix") mode:SC_EOL_LF toMenu:eolMenu];
	[self addEOLItem:NppL("menu.edit.eolMac") mode:SC_EOL_CR toMenu:eolMenu];
	NSMenu *blankMenu = [self addSubmenu:NppL("menu.edit.blankOperations") toMenu:editMenu];
	[self addItem:NppL("menu.edit.trimTrailing") action:@selector(trimTrailingWhitespace:) key:@"" toMenu:blankMenu];
	[self addItem:NppL("menu.edit.trimLeading") action:@selector(trimLeadingWhitespace:) key:@"" toMenu:blankMenu];
	[self addItem:NppL("menu.edit.trimBoth") action:@selector(trimBothWhitespace:) key:@"" toMenu:blankMenu];
	[self addItem:NppL("menu.edit.tabsToSpaces") action:@selector(convertTabsToSpaces:) key:@"" toMenu:blankMenu];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.edit.readOnly") action:@selector(toggleReadOnly:) key:@"" toMenu:editMenu];

	NSMenu *searchMenu = [self addSubmenu:NppL("menu.search") toMenu:mainMenu];
	[self addItem:NppL("menu.search.find") action:@selector(findText:) key:@"f" toMenu:searchMenu];
	NSMenuItem *findInFiles = [self addItem:NppL("menu.search.findInFiles") action:@selector(findInFiles:) key:@"f" toMenu:searchMenu];
	findInFiles.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[self addItem:NppL("menu.search.findNext") action:@selector(findNextText:) key:@"g" toMenu:searchMenu];
	NSMenuItem *findPrevious = [self addItem:NppL("menu.search.findPrevious") action:@selector(findPreviousText:) key:@"G" toMenu:searchMenu];
	findPrevious.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	NSMenuItem *replace = [self addItem:NppL("menu.search.replace") action:@selector(replaceText:) key:@"f" toMenu:searchMenu];
	replace.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
	NSMenuItem *mark = [self addItem:NppL("menu.search.mark") action:@selector(markText:) key:@"m" toMenu:searchMenu];
	mark.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[searchMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.search.goToLine") action:@selector(goToLine:) key:@"l" toMenu:searchMenu];
	[self addItem:NppL("menu.search.matchingBrace") action:@selector(goToMatchingBrace:) key:@"b" toMenu:searchMenu];
	[self addItem:NppL("menu.search.selectBraces") action:@selector(selectBetweenBraces:) key:@"" toMenu:searchMenu];
	[searchMenu addItem:[NSMenuItem separatorItem]];
	NSMenu *bookmarkMenu = [self addSubmenu:NppL("menu.search.bookmark") toMenu:searchMenu];
	[self addItem:NppL("menu.search.toggleBookmark") action:@selector(toggleBookmark:) key:@"" toMenu:bookmarkMenu];
	[self addItem:NppL("menu.search.nextBookmark") action:@selector(nextBookmark:) key:@"" toMenu:bookmarkMenu];
	[self addItem:NppL("menu.search.previousBookmark") action:@selector(previousBookmark:) key:@"" toMenu:bookmarkMenu];
	[self addItem:NppL("menu.search.clearBookmarks") action:@selector(clearBookmarks:) key:@"" toMenu:bookmarkMenu];

	NSMenu *viewMenu = [self addSubmenu:NppL("menu.view") toMenu:mainMenu];
	[self addItem:NppL("menu.view.alwaysOnTop") action:@selector(toggleAlwaysOnTop:) key:@"" toMenu:viewMenu];
	[self addItem:NppL("menu.view.fullScreen") action:@selector(toggleFullScreen:) key:@"" toMenu:viewMenu];
	NSMenuItem *markdownPreview = [self addItem:NppL("menu.view.markdownPreview") action:@selector(toggleMarkdownPreview:) key:@"M" toMenu:viewMenu];
	markdownPreview.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[self addDisabledItem:NppL("menu.view.postIt") toMenu:viewMenu];
	[self addDisabledItem:NppL("menu.view.distractionFree") toMenu:viewMenu];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	NSMenu *symbolMenu = [self addSubmenu:NppL("menu.view.showSymbol") toMenu:viewMenu];
	[self addItem:NppL("menu.view.spacesTabs") action:@selector(toggleWhitespace:) key:@"" toMenu:symbolMenu];
	[self addItem:NppL("menu.view.eol") action:@selector(toggleEOLVisibility:) key:@"" toMenu:symbolMenu];
	[self addItem:NppL("menu.view.allCharacters") action:@selector(toggleAllCharacters:) key:@"" toMenu:symbolMenu];
	[self addItem:NppL("menu.view.indentGuide") action:@selector(toggleIndentGuides:) key:@"" toMenu:symbolMenu];
	NSMenu *zoomMenu = [self addSubmenu:NppL("menu.view.zoom") toMenu:viewMenu];
	[self addItem:NppL("menu.view.zoomIn") action:@selector(zoomIn:) key:@"+" toMenu:zoomMenu];
	[self addItem:NppL("menu.view.zoomOut") action:@selector(zoomOut:) key:@"-" toMenu:zoomMenu];
	[self addItem:NppL("menu.view.zoomReset") action:@selector(zoomReset:) key:@"0" toMenu:zoomMenu];
	NSMenu *tabMenu = [self addSubmenu:NppL("menu.view.tab") toMenu:viewMenu];
	[self addItem:NppL("menu.view.firstTab") action:@selector(selectFirstTab:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.view.lastTab") action:@selector(selectLastTab:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.window.nextTab") action:@selector(selectNextTab:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.window.previousTab") action:@selector(selectPreviousTab:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.view.moveTabForward") action:@selector(moveTabForward:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.view.moveTabBackward") action:@selector(moveTabBackward:) key:@"" toMenu:tabMenu];
	[self addItem:NppL("menu.view.wordWrap") action:@selector(toggleWordWrap:) key:@"" toMenu:viewMenu];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.view.foldAll") action:@selector(foldAll:) key:@"" toMenu:viewMenu];
	[self addItem:NppL("menu.view.unfoldAll") action:@selector(unfoldAll:) key:@"" toMenu:viewMenu];
	[self addItem:NppL("menu.view.foldCurrent") action:@selector(toggleCurrentFold:) key:@"" toMenu:viewMenu];
	[viewMenu addItem:[NSMenuItem separatorItem]];
	[self addDisabledItem:NppL("menu.view.folderWorkspace") toMenu:viewMenu];
	[self addDisabledItem:NppL("menu.view.documentMap") toMenu:viewMenu];
	[self addItem:NppL("menu.view.documentList") action:@selector(showDocumentList:) key:@"" toMenu:viewMenu];
	[self addDisabledItem:NppL("menu.view.functionList") toMenu:viewMenu];

	NSMenu *encodingMenu = [self addSubmenu:NppL("menu.encoding") toMenu:mainMenu];
	[self addEncodingItem:@"ANSI" encoding:NSISOLatin1StringEncoding bom:NO toMenu:encodingMenu];
	[self addEncodingItem:@"UTF-8" encoding:NSUTF8StringEncoding bom:NO toMenu:encodingMenu];
	[self addEncodingItem:@"UTF-8-BOM" encoding:NSUTF8StringEncoding bom:YES toMenu:encodingMenu];
	[self addEncodingItem:@"UTF-16 BE BOM" encoding:NSUTF16BigEndianStringEncoding bom:YES toMenu:encodingMenu];
	[self addEncodingItem:@"UTF-16 LE BOM" encoding:NSUTF16LittleEndianStringEncoding bom:YES toMenu:encodingMenu];
	NSMenu *charsetMenu = [self addSubmenu:NppL("menu.encoding.characterSets") toMenu:encodingMenu];
	[self addEncodingItem:@"Big5 (Traditional)" encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5) toMenu:charsetMenu];
	[self addEncodingItem:@"GB2312 (Simplified)" encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80) toMenu:charsetMenu];
	[self addEncodingItem:@"Shift-JIS" encoding:NSShiftJISStringEncoding toMenu:charsetMenu];
	[self addEncodingItem:@"Windows-1251" encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsCyrillic) toMenu:charsetMenu];
	[self addEncodingItem:@"Windows-1252" encoding:NSWindowsCP1252StringEncoding toMenu:charsetMenu];
	[self addEncodingItem:@"ISO 8859-1" encoding:NSISOLatin1StringEncoding toMenu:charsetMenu];

	NSMenu *languageMenu = [self addSubmenu:NppL("menu.language") toMenu:mainMenu];
	NSMenuItem *plainText = [self addItem:NppL("menu.language.plainText") action:@selector(selectLanguage:) key:@"" toMenu:languageMenu];
	plainText.representedObject = [self.languageCatalog definitionWithName:@"normal"];
	[languageMenu addItem:[NSMenuItem separatorItem]];
	NSMutableDictionary<NSString *, NSMenu *> *letterMenus = [NSMutableDictionary dictionary];
	for (NppMacLanguageDefinition *definition in self.languageCatalog.allLanguages) {
		NSString *letter = definition.displayName.length > 0 ? [definition.displayName substringToIndex:1].uppercaseString : @"#";
		NSMenu *letterMenu = letterMenus[letter];
		if (!letterMenu) {
			letterMenu = [self addSubmenu:letter toMenu:languageMenu];
			letterMenus[letter] = letterMenu;
		}
		NSMenuItem *item = [self addItem:definition.displayName action:@selector(selectLanguage:) key:@"" toMenu:letterMenu];
		item.representedObject = definition;
	}
	[languageMenu addItem:[NSMenuItem separatorItem]];
	[self addDisabledItem:NppL("menu.language.define") toMenu:languageMenu];

	NSMenu *settingsMenu = [self addSubmenu:NppL("menu.settings") toMenu:mainMenu];
	[self addItem:NppL("menu.app.preferences") action:@selector(showPreferences:) key:@"" toMenu:settingsMenu];
	[self addItem:NppL("menu.settings.fileAssociations") action:@selector(showFileAssociations:) key:@"" toMenu:settingsMenu];
	[self addDisabledItem:NppL("menu.settings.style") toMenu:settingsMenu];
	[self addDisabledItem:NppL("menu.settings.shortcuts") toMenu:settingsMenu];
	NSMenu *importMenu = [self addSubmenu:NppL("menu.settings.import") toMenu:settingsMenu];
	[self addDisabledItem:NppL("menu.settings.importPlugins") toMenu:importMenu];
	[self addDisabledItem:NppL("menu.settings.importThemes") toMenu:importMenu];
	[self addDisabledItem:NppL("menu.settings.contextMenu") toMenu:settingsMenu];

	NSMenu *toolsMenu = [self addSubmenu:NppL("menu.tools") toMenu:mainMenu];
	NSMenuItem *formatCurrent = [self addItem:NppL("menu.tools.formatCurrent") action:@selector(formatCurrentDocument:) key:@"l" toMenu:toolsMenu];
	formatCurrent.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
	NSMenu *formatAsMenu = [self addSubmenu:NppL("menu.tools.formatAs") toMenu:toolsMenu];
	for (NSDictionary *formatter in @[
		@{@"title": @"JSON", @"language": @"json"},
		@{@"title": @"JavaScript", @"language": @"javascript"},
		@{@"title": @"HTML", @"language": @"html"},
		@{@"title": @"Java", @"language": @"java"},
		@{@"title": @"C", @"language": @"c"},
		@{@"title": @"C++", @"language": @"cpp"},
		@{@"title": @"C#", @"language": @"csharp"},
		@{@"title": @"Go", @"language": @"go"},
		@{@"title": @"Python", @"language": @"python"}
	]) {
		NSMenuItem *item = [self addItem:formatter[@"title"] action:@selector(formatDocumentAs:) key:@"" toMenu:formatAsMenu];
		item.representedObject = formatter[@"language"];
	}
	[toolsMenu addItem:[NSMenuItem separatorItem]];
	for (NSDictionary *hash in @[@{@"title": @"MD5", @"algorithm": @"md5"},
		@{@"title": @"SHA-1", @"algorithm": @"sha1"},
		@{@"title": @"SHA-256", @"algorithm": @"sha256"},
		@{@"title": @"SHA-512", @"algorithm": @"sha512"}]) {
		NSMenu *hashMenu = [self addSubmenu:hash[@"title"] toMenu:toolsMenu];
		NSMenuItem *generate = [self addItem:NppL("menu.tools.generate") action:@selector(generateHash:) key:@"" toMenu:hashMenu];
		generate.representedObject = hash[@"algorithm"];
		NSMenuItem *files = [self addItem:NppL("menu.tools.generateFiles") action:@selector(generateHashFromFiles:) key:@"" toMenu:hashMenu];
		files.representedObject = hash[@"algorithm"];
		NSMenuItem *selection = [self addItem:NppL("menu.tools.generateSelection") action:@selector(copySelectionHash:) key:@"" toMenu:hashMenu];
		selection.representedObject = hash[@"algorithm"];
	}

	NSMenu *macroMenu = [self addSubmenu:NppL("menu.macro") toMenu:mainMenu];
	[self addItem:NppL("menu.macro.start") action:@selector(startMacroRecording:) key:@"" toMenu:macroMenu];
	[self addItem:NppL("menu.macro.stop") action:@selector(stopMacroRecording:) key:@"" toMenu:macroMenu];
	[self addItem:NppL("menu.macro.playback") action:@selector(playbackMacro:) key:@"" toMenu:macroMenu];
	[self addDisabledItem:NppL("menu.macro.save") toMenu:macroMenu];
	[self addItem:NppL("menu.macro.runMultiple") action:@selector(runMacroMultipleTimes:) key:@"" toMenu:macroMenu];

	NSMenu *runMenu = [self addSubmenu:NppL("menu.run") toMenu:mainMenu];
	[self addItem:NppL("menu.run.run") action:@selector(runCommand:) key:@"r" toMenu:runMenu];
	[self addDisabledItem:NppL("menu.run.validateShortcuts") toMenu:runMenu];

	NSMenu *pluginsMenu = [self addSubmenu:NppL("menu.plugins") toMenu:mainMenu];
	[self addItem:NppL("menu.plugins.openFolder") action:@selector(openPluginsFolder:) key:@"" toMenu:pluginsMenu];

	NSMenu *windowMenu = [self addSubmenu:NppL("menu.window") toMenu:mainMenu];
	NSMenu *sortMenu = [self addSubmenu:NppL("menu.window.sort") toMenu:windowMenu];
	[self addItem:NppL("menu.window.sortNameAsc") action:@selector(sortDocumentsByNameAscending:) key:@"" toMenu:sortMenu];
	[self addItem:NppL("menu.window.sortNameDesc") action:@selector(sortDocumentsByNameDescending:) key:@"" toMenu:sortMenu];
	[self addItem:NppL("menu.window.sortPathAsc") action:@selector(sortDocumentsByPathAscending:) key:@"" toMenu:sortMenu];
	[self addItem:NppL("menu.window.sortPathDesc") action:@selector(sortDocumentsByPathDescending:) key:@"" toMenu:sortMenu];
	[self addItem:NppL("menu.window.windows") action:@selector(showDocumentList:) key:@"" toMenu:windowMenu];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *nextTab = [self addItem:NppL("menu.window.nextTab") action:@selector(selectNextTab:) key:@"\t" toMenu:windowMenu];
	nextTab.keyEquivalentModifierMask = NSEventModifierFlagControl;
	NSMenuItem *previousTab = [self addItem:NppL("menu.window.previousTab") action:@selector(selectPreviousTab:) key:@"\t" toMenu:windowMenu];
	previousTab.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagShift;
	NSApp.windowsMenu = windowMenu;

	NSMenu *helpMenu = [self addSubmenu:NppL("menu.help") toMenu:mainMenu];
	[self addItem:NppL("menu.help.commandLine") action:@selector(showCommandLineHelp:) key:@"" toMenu:helpMenu];
	[helpMenu addItem:[NSMenuItem separatorItem]];
	[self addHelpURLItem:NppL("menu.help.home") url:@"https://notepad-plus-plus.org/" toMenu:helpMenu];
	[self addHelpURLItem:NppL("menu.help.project") url:@"https://github.com/notepad-plus-plus/notepad-plus-plus" toMenu:helpMenu];
	[self addHelpURLItem:NppL("menu.help.manual") url:@"https://npp-user-manual.org/" toMenu:helpMenu];
	[self addHelpURLItem:NppL("menu.help.community") url:@"https://community.notepad-plus-plus.org/" toMenu:helpMenu];
	[helpMenu addItem:[NSMenuItem separatorItem]];
	[self addItem:NppL("menu.help.debug") action:@selector(showDebugInfo:) key:@"" toMenu:helpMenu];
	[self addItem:NppL("menu.help.about") action:@selector(orderFrontStandardAboutPanel:) key:@"" toMenu:helpMenu].target = NSApp;
}

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action key:(NSString *)key toMenu:(NSMenu *)menu {
	NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
	item.target = self;
	return item;
}

- (NSMenu *)addSubmenu:(NSString *)title toMenu:(NSMenu *)menu {
	NSMenuItem *item = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
	NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
	item.submenu = submenu;
	return submenu;
}

- (NSMenuItem *)addDisabledItem:(NSString *)title toMenu:(NSMenu *)menu {
	NSMenuItem *item = [menu addItemWithTitle:title action:nil keyEquivalent:@""];
	item.enabled = NO;
	return item;
}

- (void)addEOLItem:(NSString *)title mode:(NSInteger)mode toMenu:(NSMenu *)menu {
	NSMenuItem *item = [self addItem:title action:@selector(convertEOL:) key:@"" toMenu:menu];
	item.representedObject = @(mode);
}

- (void)addEncodingItem:(NSString *)title encoding:(NSStringEncoding)encoding toMenu:(NSMenu *)menu {
	[self addEncodingItem:title encoding:encoding bom:NO toMenu:menu];
}

- (void)addEncodingItem:(NSString *)title encoding:(NSStringEncoding)encoding bom:(BOOL)bom toMenu:(NSMenu *)menu {
	NSMenuItem *item = [self addItem:title action:@selector(selectEncoding:) key:@"" toMenu:menu];
	item.representedObject = @{@"encoding": @(encoding), @"bom": @(bom)};
}

- (void)addHelpURLItem:(NSString *)title url:(NSString *)url toMenu:(NSMenu *)menu {
	NSMenuItem *item = [self addItem:title action:@selector(openHelpURL:) key:@"" toMenu:menu];
	item.representedObject = url;
}

- (void)createEditorWindow {
	NSRect frame = NSMakeRect(0, 0, 980, 680);
	NSWindowStyleMask style = NSWindowStyleMaskTitled |
		NSWindowStyleMaskClosable |
		NSWindowStyleMaskMiniaturizable |
		NSWindowStyleMaskResizable;
	self.window = [[NSWindow alloc] initWithContentRect:frame
		styleMask:style
		backing:NSBackingStoreBuffered
		defer:NO];
	self.window.delegate = self;
	self.window.minSize = NSMakeSize(520, 360);
	self.window.level = self.preferencesController.alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
	[self.window center];
	NppMacFileDropView *contentView = [[NppMacFileDropView alloc] initWithFrame:self.window.contentView.bounds];
	contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	contentView.delegate = self;
	self.window.contentView = contentView;

	NSRect contentBounds = self.window.contentView.bounds;
	NSRect statusFrame = NSMakeRect(0, 0, contentBounds.size.width, 24);
	NSRect editorFrame = NSMakeRect(0, 24, contentBounds.size.width, contentBounds.size.height - 94);
	NSRect tabFrame = NSMakeRect(0, contentBounds.size.height - 70, contentBounds.size.width, 32);
	NSRect toolBarFrame = NSMakeRect(0, contentBounds.size.height - 38, contentBounds.size.width, 38);

	self.statusBar = [[NSTextField alloc] initWithFrame:statusFrame];
	self.statusBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
	self.statusBar.bezeled = NO;
	self.statusBar.drawsBackground = YES;
	self.statusBar.backgroundColor = [NSColor controlBackgroundColor];
	self.statusBar.editable = NO;
	self.statusBar.selectable = NO;
	self.statusBar.font = [NSFont systemFontOfSize:12];
	self.statusBar.textColor = [NSColor secondaryLabelColor];
	self.statusBar.stringValue = NppL("status.plainText");
	[self.window.contentView addSubview:self.statusBar];

	self.tabBar = [[NppMacTabBarView alloc] initWithFrame:tabFrame];
	self.tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	self.tabBar.delegate = self;
	[self.window.contentView addSubview:self.tabBar];

	self.toolBar = [[NppMacToolBarView alloc] initWithFrame:toolBarFrame target:self];
	self.toolBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	[self.window.contentView addSubview:self.toolBar];

	self.editor = [[ScintillaView alloc] initWithFrame:editorFrame];
	self.editor.delegate = self;
	self.editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[self.window.contentView addSubview:self.editor];
	[self configureEditor];
	self.findPanelController = [[NppMacFindPanelController alloc] initWithEditor:self.editor ownerWindow:self.window];
	self.markdownPreviewController = [[NppMacMarkdownPreviewController alloc] init];
	__weak NppMacAppDelegate *weakSelf = self;
	self.findPanelController.openDocumentsProvider = ^NSArray<NppMacFindDocumentSnapshot *> *{
		return [weakSelf findDocumentSnapshots];
	};
	self.findPanelController.replaceOpenDocumentHandler = ^(NSUInteger documentIndex, NSString *text) {
		[weakSelf replaceDocumentAtIndex:documentIndex withText:text];
	};
	self.documents = [NSMutableArray array];
	self.currentDocumentIndex = NSNotFound;
	[self newDocument:nil];
	[self.window makeKeyAndOrderFront:nil];
}

- (void)fileDropView:(NppMacFileDropView *)dropView openFileURLs:(NSArray<NSURL *> *)fileURLs {
	(void)dropView;
	BOOL openedAny = NO;
	for (NSURL *url in fileURLs) openedAny = [self openURL:url] || openedAny;
	if (openedAny) {
		[NSApp activateIgnoringOtherApps:YES];
		[self.window makeKeyAndOrderFront:nil];
	}
}

- (void)configureEditor {
	[self.editor suspendDrawing:YES];
	[self.editor setGeneralProperty:SCI_SETCODEPAGE value:SC_CP_UTF8];
	[self.editor setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:self.preferencesController.fontName];
	[self.editor setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:self.preferencesController.fontSize];
	[self.editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT fromHTML:@"#1F2328"];
	[self.editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT fromHTML:@"#FFFFFF"];
	[self.editor setGeneralProperty:SCI_STYLECLEARALL value:0];
	[self.editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER fromHTML:@"#6E7781"];
	[self.editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER fromHTML:@"#F6F8FA"];
	[self.editor setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
	[self.editor setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:self.preferencesController.showLineNumbers ? 48 : 0];
	[self.editor setGeneralProperty:SCI_SETMARGINTYPEN parameter:1 value:SC_MARGIN_SYMBOL];
	[self.editor setGeneralProperty:SCI_SETMARGINMASKN parameter:1 value:(1 << 24)];
	[self.editor setGeneralProperty:SCI_SETMARGINWIDTHN parameter:1 value:16];
	[self.editor setGeneralProperty:SCI_MARKERDEFINE parameter:24 value:SC_MARK_BOOKMARK];
	[self.editor setColorProperty:SCI_MARKERSETFORE parameter:24 value:NSColor.whiteColor];
	[self.editor setColorProperty:SCI_MARKERSETBACK parameter:24 value:NSColor.systemBlueColor];
	[self.editor setGeneralProperty:SCI_SETTABWIDTH value:self.preferencesController.tabWidth];
	[self.editor setGeneralProperty:SCI_SETUSETABS value:self.preferencesController.useTabs ? 1 : 0];
	[self.editor setGeneralProperty:SCI_SETINDENT value:self.preferencesController.tabWidth];
	[self.editor setGeneralProperty:SCI_SETWRAPMODE value:self.preferencesController.wrapLines ? SC_WRAP_WORD : SC_WRAP_NONE];
	[self.editor setGeneralProperty:SCI_SETCARETLINEVISIBLE value:0];
	[self.editor setColorProperty:SCI_SETSELBACK parameter:1 fromHTML:@"#005FCC"];
	[self.editor setColorProperty:SCI_SETSELFORE parameter:1 fromHTML:@"#FFFFFF"];
	[self.editor suspendDrawing:NO];
}

- (void)applyEditorPreferences {
	if (!self.editor) {
		return;
	}
	[self.editor suspendDrawing:YES];
	[self.editor setGeneralProperty:SCI_SETTABWIDTH value:self.preferencesController.tabWidth];
	[self.editor setGeneralProperty:SCI_SETUSETABS value:self.preferencesController.useTabs ? 1 : 0];
	[self.editor setGeneralProperty:SCI_SETINDENT value:self.preferencesController.tabWidth];
	[self.editor setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:self.preferencesController.showLineNumbers ? 48 : 0];
	[self.editor setGeneralProperty:SCI_SETWRAPMODE value:self.preferencesController.wrapLines ? SC_WRAP_WORD : SC_WRAP_NONE];
	[self applyLexerForURL:self.currentDocument.url];
	[self.editor suspendDrawing:NO];
}

- (void)loadLexilla {
	NSString *libraryPath = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"liblexilla.dylib"];
	self.lexillaHandle = dlopen(libraryPath.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
	if (!self.lexillaHandle) {
		NSLog(@"Could not load Lexilla: %s", dlerror());
	}
}

- (void)newDocument:(id)sender {
	(void)sender;
	[self appendDocumentWithText:@"" url:nil];
}

- (void)openDocument:(id)sender {
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = YES;
	panel.canChooseDirectories = NO;
	panel.canChooseFiles = YES;
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}

	for (NSURL *url in panel.URLs) {
		[self openURL:url];
	}
}

- (void)saveDocument:(id)sender {
	(void)sender;
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return;
	}
	if (!document.url) {
		[self saveDocumentAs:nil];
		return;
	}
	[self writeCurrentDocumentToURL:document.url];
}

- (void)saveDocumentAs:(id)sender {
	(void)sender;
	[self saveCurrentDocumentAs];
}

- (void)reloadDocument:(id)sender {
	(void)sender;
	NppMacDocument *document = self.currentDocument;
	if (!document.url) {
		return;
	}
	if (document.dirty || [self.editor message:SCI_GETMODIFY]) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NppL("alert.reload.title");
		alert.informativeText = NppL("alert.reload.message");
		[alert addButtonWithTitle:NppL("common.reload")];
		[alert addButtonWithTitle:NppL("common.cancel")];
		if ([alert runModal] != NSAlertFirstButtonReturn) {
			return;
		}
	}
	[self reloadCurrentDocumentFromDisk];
}

- (BOOL)saveCurrentDocumentAs {
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return NO;
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = document.url ? document.url.lastPathComponent : NppL("common.untitledFile");
	if ([panel runModal] != NSModalResponseOK) {
		return NO;
	}
	document.url = panel.URL;
	[self applyLexerForURL:panel.URL];
	return [self writeCurrentDocumentToURL:panel.URL];
}

- (void)closeDocument:(id)sender {
	(void)sender;
	if (self.currentDocumentIndex != NSNotFound) {
		[self closeDocumentAtIndex:(NSUInteger)self.currentDocumentIndex];
	}
}

- (void)selectNextTab:(id)sender {
	(void)sender;
	if (self.documents.count > 1) {
		NSUInteger next = ((NSUInteger)self.currentDocumentIndex + 1) % self.documents.count;
		[self switchToDocumentAtIndex:next];
	}
}

- (void)selectPreviousTab:(id)sender {
	(void)sender;
	if (self.documents.count > 1) {
		NSUInteger current = (NSUInteger)self.currentDocumentIndex;
		NSUInteger previous = current == 0 ? self.documents.count - 1 : current - 1;
		[self switchToDocumentAtIndex:previous];
	}
}

- (void)tabBarView:(NppMacTabBarView *)tabBar didSelectTabAtIndex:(NSUInteger)index {
	(void)tabBar;
	[self switchToDocumentAtIndex:index];
}

- (void)tabBarView:(NppMacTabBarView *)tabBar didRequestCloseTabAtIndex:(NSUInteger)index {
	(void)tabBar;
	[self closeDocumentAtIndex:index];
}

- (void)tabBarViewDidRequestNewTab:(NppMacTabBarView *)tabBar {
	(void)tabBar;
	[self newDocument:nil];
}

- (void)tabBarView:(NppMacTabBarView *)tabBar
	didMoveTabFromIndex:(NSUInteger)sourceIndex
	toIndex:(NSUInteger)destinationIndex {
	(void)tabBar;
	if (sourceIndex >= self.documents.count || destinationIndex >= self.documents.count || sourceIndex == destinationIndex) {
		return;
	}
	NppMacDocument *activeDocument = self.currentDocument;
	NppMacDocument *movedDocument = self.documents[sourceIndex];
	[self.documents removeObjectAtIndex:sourceIndex];
	[self.documents insertObject:movedDocument atIndex:destinationIndex];
	self.currentDocumentIndex = (NSInteger)[self.documents indexOfObjectIdenticalTo:activeDocument];
	[self rebuildTabBar];
	[self persistSession];
}

- (void)undo:(id)sender {
	(void)sender;
	[self.editor message:SCI_UNDO];
}

- (void)redo:(id)sender {
	(void)sender;
	[self.editor message:SCI_REDO];
}

- (void)cut:(id)sender {
	(void)sender;
	[self.editor message:SCI_CUT];
}

- (void)copy:(id)sender {
	(void)sender;
	[self.editor message:SCI_COPY];
}

- (void)paste:(id)sender {
	(void)sender;
	[self.editor message:SCI_PASTE];
}

- (void)selectAll:(id)sender {
	(void)sender;
	[self.editor message:SCI_SELECTALL];
}

- (void)deleteSelection:(id)sender {
	(void)sender;
	[self.editor message:SCI_CLEAR];
}

- (void)openContainingFolder:(id)sender {
	(void)sender;
	NSURL *url = self.currentDocument.url;
	if (url) {
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
	}
}

- (void)openContainingFolderInTerminal:(id)sender {
	(void)sender;
	NSURL *directory = self.currentDocument.url.URLByDeletingLastPathComponent;
	if (!directory) {
		return;
	}
	NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\" to do script \"cd %@\"",
		[[directory.path stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
			stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
	NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
	[appleScript executeAndReturnError:nil];
}

- (void)openInDefaultViewer:(id)sender {
	(void)sender;
	if (self.currentDocument.url) {
		[NSWorkspace.sharedWorkspace openURL:self.currentDocument.url];
	}
}

- (void)saveCopyAs:(id)sender {
	(void)sender;
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = self.currentDocument.url.lastPathComponent ?: NppL("common.untitledFile");
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	NSError *error = nil;
	NSString *text = self.editor.string ?: @"";
	if (![[self encodedDataForText:text document:self.currentDocument] writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
		[self showError:error message:NppL("alert.save.error")];
	}
}

- (void)saveAllDocuments:(id)sender {
	(void)sender;
	NSInteger original = self.currentDocumentIndex;
	for (NSUInteger index = 0; index < self.documents.count; ++index) {
		[self switchToDocumentAtIndex:index];
		if (self.currentDocument.dirty && (!self.currentDocument.url ? ![self saveCurrentDocumentAs] :
			![self writeCurrentDocumentToURL:self.currentDocument.url])) {
			break;
		}
	}
	if (original != NSNotFound && (NSUInteger)original < self.documents.count) {
		[self switchToDocumentAtIndex:(NSUInteger)original];
	}
}

- (void)renameDocument:(id)sender {
	(void)sender;
	NSURL *source = self.currentDocument.url;
	if (!source) {
		[self saveDocumentAs:nil];
		return;
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.directoryURL = source.URLByDeletingLastPathComponent;
	panel.nameFieldStringValue = source.lastPathComponent;
	if ([panel runModal] != NSModalResponseOK || [panel.URL isEqual:source]) {
		return;
	}
	NSError *error = nil;
	if (![NSFileManager.defaultManager moveItemAtURL:source toURL:panel.URL error:&error]) {
		[self showError:error message:NppL("alert.rename.error")];
		return;
	}
	self.currentDocument.url = panel.URL;
	[self applyLexerForURL:panel.URL];
	[self rebuildTabBar];
	[self updateWindowTitle];
}

- (void)closeAllDocuments:(id)sender {
	(void)sender;
	while (self.documents.count > 1) {
		if (![self closeDocumentAtIndex:self.documents.count - 1]) return;
	}
	if (self.documents.count == 1) [self closeDocumentAtIndex:0];
}

- (void)closeOtherDocuments:(id)sender {
	(void)sender;
	NppMacDocument *active = self.currentDocument;
	for (NSInteger index = (NSInteger)self.documents.count - 1; index >= 0; --index) {
		if (self.documents[(NSUInteger)index] != active && ![self closeDocumentAtIndex:(NSUInteger)index]) return;
	}
}

- (void)closeDocumentsToLeft:(id)sender {
	(void)sender;
	for (NSInteger index = self.currentDocumentIndex - 1; index >= 0; --index) {
		if (![self closeDocumentAtIndex:(NSUInteger)index]) return;
	}
}

- (void)closeDocumentsToRight:(id)sender {
	(void)sender;
	for (NSInteger index = (NSInteger)self.documents.count - 1; index > self.currentDocumentIndex; --index) {
		if (![self closeDocumentAtIndex:(NSUInteger)index]) return;
	}
}

- (void)closeUnchangedDocuments:(id)sender {
	(void)sender;
	for (NSInteger index = (NSInteger)self.documents.count - 1; index >= 0; --index) {
		if (!self.documents[(NSUInteger)index].dirty && ![self closeDocumentAtIndex:(NSUInteger)index]) return;
	}
}

- (void)moveDocumentToTrash:(id)sender {
	(void)sender;
	NSURL *url = self.currentDocument.url;
	if (!url) return;
	NSURL *result = nil;
	NSError *error = nil;
	if (![NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:&result error:&error]) {
		[self showError:error message:NppL("alert.trash.error")];
		return;
	}
	self.currentDocument.dirty = NO;
	[self closeDocument:nil];
}

- (NSPrintOperation *)printOperationForCurrentDocument {
	NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 612, 792)];
	textView.string = self.editor.string ?: @"";
	textView.font = [NSFont fontWithName:self.preferencesController.fontName size:self.preferencesController.fontSize];
	return [NSPrintOperation printOperationWithView:textView];
}

- (void)printDocument:(id)sender {
	(void)sender;
	[[self printOperationForCurrentDocument] runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
}

- (void)printDocumentNow:(id)sender {
	(void)sender;
	[[self printOperationForCurrentDocument] runOperation];
}

- (NSString *)selectedText {
	sptr_t length = [self.editor message:SCI_GETSELTEXT];
	if (length <= 1) return @"";
	NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
	[ScintillaView directCall:self.editor message:SCI_GETSELTEXT wParam:0 lParam:(sptr_t)data.mutableBytes];
	return [[NSString alloc] initWithBytes:data.bytes length:(NSUInteger)length - 1 encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)replaceSelectionWithText:(NSString *)text {
	[self.editor message:SCI_BEGINUNDOACTION];
	[ScintillaView directCall:self.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)text.UTF8String];
	[self.editor message:SCI_ENDUNDOACTION];
}

- (void)replaceWholeText:(NSString *)text {
	sptr_t caret = [self.editor message:SCI_GETCURRENTPOS];
	[self.editor message:SCI_BEGINUNDOACTION];
	[self.editor message:SCI_SETSEL wParam:0 lParam:[self.editor message:SCI_GETLENGTH]];
	[ScintillaView directCall:self.editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)text.UTF8String];
	[self.editor message:SCI_SETEMPTYSELECTION wParam:(uptr_t)MIN(caret, [self.editor message:SCI_GETLENGTH])];
	[self.editor message:SCI_ENDUNDOACTION];
}

- (void)insertText:(NSString *)text {
	[self replaceSelectionWithText:text];
}

- (void)insertShortDateTime:(id)sender {
	(void)sender;
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterShortStyle;
	formatter.timeStyle = NSDateFormatterShortStyle;
	[self insertText:[formatter stringFromDate:NSDate.date]];
}

- (void)insertLongDateTime:(id)sender {
	(void)sender;
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterFullStyle;
	formatter.timeStyle = NSDateFormatterLongStyle;
	[self insertText:[formatter stringFromDate:NSDate.date]];
}

- (void)copyTextToClipboard:(NSString *)text {
	if (text.length == 0) return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)copyFullPath:(id)sender { (void)sender; [self copyTextToClipboard:self.currentDocument.url.path]; }
- (void)copyFilename:(id)sender { (void)sender; [self copyTextToClipboard:self.currentDocument.url.lastPathComponent]; }
- (void)copyDirectory:(id)sender { (void)sender; [self copyTextToClipboard:self.currentDocument.url.URLByDeletingLastPathComponent.path]; }
- (void)copyAllFilenames:(id)sender {
	(void)sender;
	NSMutableArray *values = [NSMutableArray array];
	for (NppMacDocument *document in self.documents) [values addObject:document.url.lastPathComponent ?: NppL("common.untitled")];
	[self copyTextToClipboard:[values componentsJoinedByString:@"\n"]];
}
- (void)copyAllFilePaths:(id)sender {
	(void)sender;
	NSMutableArray *values = [NSMutableArray array];
	for (NppMacDocument *document in self.documents) if (document.url.path) [values addObject:document.url.path];
	[self copyTextToClipboard:[values componentsJoinedByString:@"\n"]];
}

- (void)increaseIndent:(id)sender { (void)sender; [self.editor message:SCI_TAB]; }
- (void)decreaseIndent:(id)sender { (void)sender; [self.editor message:SCI_BACKTAB]; }
- (void)uppercaseSelection:(id)sender { (void)sender; [self.editor message:SCI_UPPERCASE]; }
- (void)lowercaseSelection:(id)sender { (void)sender; [self.editor message:SCI_LOWERCASE]; }
- (void)titlecaseSelection:(id)sender { (void)sender; [self replaceSelectionWithText:self.selectedText.capitalizedString]; }
- (void)invertCaseSelection:(id)sender {
	(void)sender;
	NSString *source = self.selectedText;
	NSMutableString *result = [NSMutableString string];
	[source enumerateSubstringsInRange:NSMakeRange(0, source.length) options:NSStringEnumerationByComposedCharacterSequences
		usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
			(void)range; (void)enclosingRange; (void)stop;
			[result appendString:[substring isEqualToString:substring.uppercaseString] ? substring.lowercaseString : substring.uppercaseString];
		}];
	[self replaceSelectionWithText:result];
}

- (void)duplicateLine:(id)sender { (void)sender; [self.editor message:SCI_LINEDUPLICATE]; }
- (void)splitLines:(id)sender { (void)sender; [self.editor message:SCI_LINESSPLIT]; }
- (void)joinLines:(id)sender { (void)sender; [self.editor message:SCI_LINESJOIN]; }
- (void)moveLineUp:(id)sender { (void)sender; [self.editor message:SCI_MOVESELECTEDLINESUP]; }
- (void)moveLineDown:(id)sender { (void)sender; [self.editor message:SCI_MOVESELECTEDLINESDOWN]; }

- (NSArray<NSString *> *)documentLines {
	return [(self.editor.string ?: @"") componentsSeparatedByString:@"\n"];
}

- (void)removeDuplicateLines:(id)sender {
	(void)sender;
	NSMutableSet *seen = [NSMutableSet set];
	NSMutableArray *result = [NSMutableArray array];
	for (NSString *line in self.documentLines) if (![seen containsObject:line]) { [seen addObject:line]; [result addObject:line]; }
	[self replaceWholeText:[result componentsJoinedByString:@"\n"]];
}

- (void)removeEmptyLines:(id)sender {
	(void)sender;
	NSArray *result = [self.documentLines filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *line, NSDictionary *bindings) {
		(void)bindings; return line.length > 0;
	}]];
	[self replaceWholeText:[result componentsJoinedByString:@"\n"]];
}

- (void)removeBlankLines:(id)sender {
	(void)sender;
	NSArray *result = [self.documentLines filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *line, NSDictionary *bindings) {
		(void)bindings; return [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length > 0;
	}]];
	[self replaceWholeText:[result componentsJoinedByString:@"\n"]];
}

- (void)insertBlankLineAbove:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	sptr_t position = [self.editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
	[self.editor message:SCI_SETEMPTYSELECTION wParam:(uptr_t)position];
	[self insertText:@"\n"];
}

- (void)insertBlankLineBelow:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	sptr_t position = [self.editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
	[self.editor message:SCI_SETEMPTYSELECTION wParam:(uptr_t)position];
	[self insertText:@"\n"];
}

- (void)reverseLines:(id)sender { (void)sender; [self replaceWholeText:[[self.documentLines reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n"]]; }
- (void)sortLinesAscending:(id)sender {
	(void)sender; [self replaceWholeText:[[self.documentLines sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] componentsJoinedByString:@"\n"]];
}
- (void)sortLinesDescending:(id)sender {
	(void)sender;
	NSArray *sorted = [self.documentLines sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	[self replaceWholeText:[sorted.reverseObjectEnumerator.allObjects componentsJoinedByString:@"\n"]];
}

- (NSString *)lineCommentPrefix {
	NSString *language = self.currentDocument.languageName.lowercaseString;
	if ([language containsString:@"python"] || [language containsString:@"shell"] || [language containsString:@"make"] ||
		[language containsString:@"yaml"] || [language containsString:@"toml"]) return @"#";
	if ([language containsString:@"sql"] || [language containsString:@"lua"]) return @"--";
	return @"//";
}

- (void)transformSelectedLines:(BOOL (^)(NSString *line))predicate transform:(NSString *(^)(NSString *line))transform {
	NSInteger first = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETSELECTIONSTART]];
	NSInteger last = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETSELECTIONEND]];
	NSMutableArray *lines = [self.documentLines mutableCopy];
	for (NSInteger index = first; index <= last && index < (NSInteger)lines.count; ++index) {
		NSString *line = lines[(NSUInteger)index];
		if (!predicate || predicate(line)) lines[(NSUInteger)index] = transform(line);
	}
	[self replaceWholeText:[lines componentsJoinedByString:@"\n"]];
}

- (void)commentLines:(id)sender {
	(void)sender; NSString *prefix = self.lineCommentPrefix;
	[self transformSelectedLines:nil transform:^NSString *(NSString *line) { return [prefix stringByAppendingString:line]; }];
}
- (void)uncommentLines:(id)sender {
	(void)sender; NSString *prefix = self.lineCommentPrefix;
	[self transformSelectedLines:^BOOL(NSString *line) { return [line hasPrefix:prefix]; }
		transform:^NSString *(NSString *line) { return [line substringFromIndex:prefix.length]; }];
}
- (void)toggleLineComment:(id)sender {
	(void)sender; NSString *prefix = self.lineCommentPrefix;
	NSInteger first = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETSELECTIONSTART]];
	NSArray *lines = self.documentLines;
	BOOL uncomment = first < (NSInteger)lines.count && [lines[(NSUInteger)first] hasPrefix:prefix];
	if (uncomment) [self uncommentLines:nil]; else [self commentLines:nil];
}

- (void)convertEOL:(NSMenuItem *)sender {
	NSInteger mode = [sender.representedObject integerValue];
	[self.editor message:SCI_CONVERTEOLS wParam:(uptr_t)mode];
	[self.editor message:SCI_SETEOLMODE wParam:(uptr_t)mode];
}

- (void)trimWithLeading:(BOOL)leading trailing:(BOOL)trailing {
	NSMutableArray *result = [NSMutableArray array];
	NSRegularExpression *lead = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]+" options:0 error:nil];
	NSRegularExpression *tail = [NSRegularExpression regularExpressionWithPattern:@"[ \\t]+$" options:0 error:nil];
	for (NSString *line in self.documentLines) {
		NSString *value = line;
		if (leading) value = [lead stringByReplacingMatchesInString:value options:0 range:NSMakeRange(0, value.length) withTemplate:@""];
		if (trailing) value = [tail stringByReplacingMatchesInString:value options:0 range:NSMakeRange(0, value.length) withTemplate:@""];
		[result addObject:value];
	}
	[self replaceWholeText:[result componentsJoinedByString:@"\n"]];
}
- (void)trimTrailingWhitespace:(id)sender { (void)sender; [self trimWithLeading:NO trailing:YES]; }
- (void)trimLeadingWhitespace:(id)sender { (void)sender; [self trimWithLeading:YES trailing:NO]; }
- (void)trimBothWhitespace:(id)sender { (void)sender; [self trimWithLeading:YES trailing:YES]; }
- (void)convertTabsToSpaces:(id)sender {
	(void)sender;
	NSString *spaces = [@"" stringByPaddingToLength:(NSUInteger)MAX(self.preferencesController.tabWidth, 1) withString:@" " startingAtIndex:0];
	[self replaceWholeText:[self.editor.string stringByReplacingOccurrencesOfString:@"\t" withString:spaces]];
}
- (void)toggleReadOnly:(id)sender {
	(void)sender; [self.editor message:SCI_SETREADONLY wParam:[self.editor message:SCI_GETREADONLY] ? 0 : 1];
}

- (void)showPreferences:(id)sender {
	(void)sender;
	[self.preferencesController showPreferences];
}

- (void)showFileAssociations:(id)sender {
	(void)sender;
	[self.preferencesController showFileAssociations];
}

- (void)findText:(id)sender {
	(void)sender;
	[self.findPanelController showFindPanel];
}

- (void)findNextText:(id)sender {
	(void)sender;
	[self.findPanelController findNext];
}

- (void)findPreviousText:(id)sender {
	(void)sender;
	[self.findPanelController findPrevious];
}

- (void)replaceText:(id)sender {
	(void)sender;
	[self.findPanelController showReplacePanel];
}

- (void)findInFiles:(id)sender {
	(void)sender;
	[self.findPanelController showFindInFilesPanel];
}

- (void)markText:(id)sender {
	(void)sender;
	[self.findPanelController showMarkPanel];
}

- (void)goToLine:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = NppL("alert.goto.title");
	alert.informativeText = [NSString stringWithFormat:NppL("alert.goto.message"),
		(long)[self.editor message:SCI_GETLINECOUNT]];
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 26)];
	field.placeholderString = NppL("alert.goto.placeholder");
	alert.accessoryView = field;
	[alert addButtonWithTitle:NppL("common.go")];
	[alert addButtonWithTitle:NppL("common.cancel")];
	[alert.window setInitialFirstResponder:field];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	NSInteger lineCount = [self.editor message:SCI_GETLINECOUNT];
	NSInteger line = MIN(MAX(field.integerValue, 1), lineCount) - 1;
	[self.editor message:SCI_GOTOLINE wParam:(uptr_t)line];
	[self.editor message:SCI_SCROLLCARET];
	[self.window makeFirstResponder:self.editor];
}

- (void)goToMatchingBrace:(id)sender {
	(void)sender;
	sptr_t position = [self.editor message:SCI_GETCURRENTPOS];
	sptr_t match = [self.editor message:SCI_BRACEMATCH wParam:(uptr_t)position lParam:0];
	if (match < 0 && position > 0) {
		match = [self.editor message:SCI_BRACEMATCH wParam:(uptr_t)(position - 1) lParam:0];
	}
	if (match >= 0) {
		[self.editor message:SCI_GOTOPOS wParam:(uptr_t)match];
		[self.editor message:SCI_SCROLLCARET];
	}
}

- (void)selectBetweenBraces:(id)sender {
	(void)sender;
	sptr_t position = [self.editor message:SCI_GETCURRENTPOS];
	for (sptr_t candidate : {position, position > 0 ? position - 1 : position}) {
		sptr_t match = [self.editor message:SCI_BRACEMATCH wParam:(uptr_t)candidate lParam:0];
		if (match >= 0) {
			sptr_t start = MIN(candidate, match) + 1;
			sptr_t end = MAX(candidate, match);
			[self.editor message:SCI_SETSEL wParam:(uptr_t)start lParam:end];
			return;
		}
	}
}

- (void)toggleBookmark:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	sptr_t markers = [self.editor message:SCI_MARKERGET wParam:(uptr_t)line];
	if (markers & (1 << 24)) [self.editor message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:24];
	else [self.editor message:SCI_MARKERADD wParam:(uptr_t)line lParam:24];
}

- (void)nextBookmark:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	sptr_t target = [self.editor message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << 24)];
	if (target < 0) target = [self.editor message:SCI_MARKERNEXT wParam:0 lParam:(1 << 24)];
	if (target >= 0) [self.editor message:SCI_GOTOLINE wParam:(uptr_t)target];
}

- (void)previousBookmark:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	sptr_t target = [self.editor message:SCI_MARKERPREVIOUS wParam:(uptr_t)MAX(line - 1, 0) lParam:(1 << 24)];
	if (target < 0) target = [self.editor message:SCI_MARKERPREVIOUS wParam:(uptr_t)[self.editor message:SCI_GETLINECOUNT] lParam:(1 << 24)];
	if (target >= 0) [self.editor message:SCI_GOTOLINE wParam:(uptr_t)target];
}

- (void)clearBookmarks:(id)sender { (void)sender; [self.editor message:SCI_MARKERDELETEALL wParam:24]; }

- (void)toggleAlwaysOnTop:(id)sender {
	(void)sender;
	BOOL alwaysOnTop = self.window.level != NSFloatingWindowLevel;
	self.window.level = alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
	[self.preferencesController updateAlwaysOnTop:alwaysOnTop];
}
- (void)toggleFullScreen:(id)sender { (void)sender; [self.window toggleFullScreen:nil]; }
- (BOOL)isCurrentDocumentMarkdown {
	NSString *extension = self.currentDocument.url.pathExtension.lowercaseString ?: @"";
	return [@[@"md", @"markdown", @"mdown", @"mkd", @"mkdn", @"mdx"] containsObject:extension] ||
		[self.currentDocument.languageName.lowercaseString containsString:@"markdown"];
}

- (NSString *)markdownPreviewTitle {
	NSString *name = self.currentDocument.url.lastPathComponent ?: NppL("common.untitled");
	return [NSString stringWithFormat:NppL("preview.markdown.title"), name];
}

- (void)toggleMarkdownPreview:(id)sender {
	(void)sender;
	if (self.markdownPreviewController.previewVisible) {
		[self.markdownPreviewController.window orderOut:nil];
		return;
	}
	if (![self isCurrentDocumentMarkdown]) return;
	NSURL *baseURL = self.currentDocument.url.URLByDeletingLastPathComponent;
	[self.markdownPreviewController showMarkdown:self.editor.string ?: @"" baseURL:baseURL title:self.markdownPreviewTitle];
}

- (void)updateMarkdownPreview {
	if (!self.markdownPreviewController.previewVisible) return;
	if (![self isCurrentDocumentMarkdown]) {
		[self.markdownPreviewController.window orderOut:nil];
		return;
	}
	NSURL *baseURL = self.currentDocument.url.URLByDeletingLastPathComponent;
	[self.markdownPreviewController scheduleMarkdownUpdate:self.editor.string ?: @"" baseURL:baseURL title:self.markdownPreviewTitle];
}

- (void)toggleWhitespace:(id)sender {
	(void)sender; [self.editor message:SCI_SETVIEWWS wParam:[self.editor message:SCI_GETVIEWWS] == SCWS_INVISIBLE ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE];
}
- (void)toggleEOLVisibility:(id)sender {
	(void)sender; [self.editor message:SCI_SETVIEWEOL wParam:[self.editor message:SCI_GETVIEWEOL] ? 0 : 1];
}
- (void)toggleAllCharacters:(id)sender {
	(void)sender;
	BOOL show = [self.editor message:SCI_GETVIEWWS] == SCWS_INVISIBLE || ![self.editor message:SCI_GETVIEWEOL];
	[self.editor message:SCI_SETVIEWWS wParam:show ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE];
	[self.editor message:SCI_SETVIEWEOL wParam:show ? 1 : 0];
	[self updateToolBar];
}
- (void)toggleIndentGuides:(id)sender {
	(void)sender;
	[self.editor message:SCI_SETINDENTATIONGUIDES wParam:[self.editor message:SCI_GETINDENTATIONGUIDES] == SC_IV_NONE ? SC_IV_LOOKBOTH : SC_IV_NONE];
	[self updateToolBar];
}
- (void)zoomIn:(id)sender { (void)sender; [self.editor message:SCI_ZOOMIN]; }
- (void)zoomOut:(id)sender { (void)sender; [self.editor message:SCI_ZOOMOUT]; }
- (void)zoomReset:(id)sender { (void)sender; [self.editor message:SCI_SETZOOM wParam:0]; }
- (void)toggleWordWrap:(id)sender {
	(void)sender;
	BOOL wrapLines = [self.editor message:SCI_GETWRAPMODE] == SC_WRAP_NONE;
	[self.editor message:SCI_SETWRAPMODE wParam:wrapLines ? SC_WRAP_WORD : SC_WRAP_NONE];
	[self.preferencesController updateWrapLines:wrapLines];
	[self updateToolBar];
}
- (void)foldAll:(id)sender { (void)sender; [self.editor message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT]; }
- (void)unfoldAll:(id)sender { (void)sender; [self.editor message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND]; }
- (void)toggleCurrentFold:(id)sender {
	(void)sender;
	NSInteger line = [self.editor message:SCI_LINEFROMPOSITION wParam:[self.editor message:SCI_GETCURRENTPOS]];
	[self.editor message:SCI_TOGGLEFOLD wParam:(uptr_t)line];
}
- (void)selectFirstTab:(id)sender { (void)sender; if (self.documents.count) [self switchToDocumentAtIndex:0]; }
- (void)selectLastTab:(id)sender { (void)sender; if (self.documents.count) [self switchToDocumentAtIndex:self.documents.count - 1]; }
- (void)moveCurrentTabByOffset:(NSInteger)offset {
	NSInteger target = self.currentDocumentIndex + offset;
	if (target < 0 || target >= (NSInteger)self.documents.count) return;
	NppMacDocument *document = self.currentDocument;
	[self.documents removeObjectAtIndex:(NSUInteger)self.currentDocumentIndex];
	[self.documents insertObject:document atIndex:(NSUInteger)target];
	self.currentDocumentIndex = target;
	[self rebuildTabBar];
	[self persistSession];
}
- (void)moveTabForward:(id)sender { (void)sender; [self moveCurrentTabByOffset:1]; }
- (void)moveTabBackward:(id)sender { (void)sender; [self moveCurrentTabByOffset:-1]; }

- (void)selectEncoding:(NSMenuItem *)sender {
	NSDictionary *choice = sender.representedObject;
	self.currentDocument.encoding = (NSStringEncoding)[choice[@"encoding"] unsignedIntegerValue];
	self.currentDocument.writeBOM = [choice[@"bom"] boolValue];
	self.currentDocument.dirty = YES;
	[self rebuildTabBar];
	[self updateStatusBar];
}

- (void)selectLanguage:(NSMenuItem *)sender {
	NppMacLanguageDefinition *definition = sender.representedObject;
	if (!definition) return;
	self.currentDocument.languageName = definition.name.length == 0 || [definition.name isEqualToString:@"normal"] ?
		NppL("status.plainText") : definition.displayName;
	const char *lexerName = definition.lexerName.length > 0 ? definition.lexerName.UTF8String : nullptr;
	[self applyBaseStyles];
	[self setLexerNamed:lexerName];
	[self applyStylesForLexer:lexerName];
	[self.editor message:SCI_COLOURISE wParam:0 lParam:-1];
	[self updateStatusBar];
	[self updateMarkdownPreview];
}

- (void)formatCurrentDocument:(id)sender {
	(void)sender;
	NSString *language = [NppMacCodeFormatter languageIdentifierForURL:self.currentDocument.url
		languageName:self.currentDocument.languageName];
	if (!language) {
		[self showFormatterError:nil message:NppL("alert.format.unsupported")];
		return;
	}
	[self formatDocumentWithLanguageIdentifier:language];
}

- (void)formatDocumentAs:(NSMenuItem *)sender {
	[self formatDocumentWithLanguageIdentifier:sender.representedObject];
}

- (void)formatDocumentWithLanguageIdentifier:(NSString *)languageIdentifier {
	NSError *error = nil;
	NSString *formatted = [NppMacCodeFormatter formatText:self.editor.string ?: @""
		languageIdentifier:languageIdentifier fileURL:self.currentDocument.url error:&error];
	if (!formatted) {
		[self showFormatterError:error message:NppL("alert.format.failed")];
		return;
	}
	if (![formatted isEqualToString:self.editor.string ?: @""]) {
		[self replaceWholeText:formatted];
		[self updateDirtyState];
		[self updateMarkdownPreview];
	}
}

- (void)showFormatterError:(NSError *)error message:(NSString *)message {
	NSAlert *alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = NppL("alert.format.title");
	alert.informativeText = error.localizedDescription.length ? error.localizedDescription : message;
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
}

- (NSString *)hashForData:(NSData *)data algorithm:(NSString *)algorithm {
	unsigned char digest[CC_SHA512_DIGEST_LENGTH] = {0};
	NSUInteger length = 0;
	if ([algorithm isEqualToString:@"md5"]) { CC_MD5(data.bytes, (CC_LONG)data.length, digest); length = CC_MD5_DIGEST_LENGTH; }
	else if ([algorithm isEqualToString:@"sha1"]) { CC_SHA1(data.bytes, (CC_LONG)data.length, digest); length = CC_SHA1_DIGEST_LENGTH; }
	else if ([algorithm isEqualToString:@"sha256"]) { CC_SHA256(data.bytes, (CC_LONG)data.length, digest); length = CC_SHA256_DIGEST_LENGTH; }
	else { CC_SHA512(data.bytes, (CC_LONG)data.length, digest); length = CC_SHA512_DIGEST_LENGTH; }
	NSMutableString *result = [NSMutableString stringWithCapacity:length * 2];
	for (NSUInteger index = 0; index < length; ++index) [result appendFormat:@"%02x", digest[index]];
	return result;
}

- (void)showTextResult:(NSString *)text title:(NSString *)title {
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = title;
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 520, 24)];
	field.editable = NO; field.selectable = YES; field.stringValue = text ?: @"";
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
}

- (void)generateHash:(NSMenuItem *)sender {
	NSData *data = [(self.editor.string ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
	[self showTextResult:[self hashForData:data algorithm:sender.representedObject] title:sender.menu.title];
}
- (void)copySelectionHash:(NSMenuItem *)sender {
	NSData *data = [self.selectedText dataUsingEncoding:NSUTF8StringEncoding];
	[self copyTextToClipboard:[self hashForData:data algorithm:sender.representedObject]];
}
- (void)generateHashFromFiles:(NSMenuItem *)sender {
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = YES;
	if ([panel runModal] != NSModalResponseOK) return;
	NSMutableArray *lines = [NSMutableArray array];
	for (NSURL *url in panel.URLs) {
		NSData *data = [NSData dataWithContentsOfURL:url];
		if (data) [lines addObject:[NSString stringWithFormat:@"%@  %@", [self hashForData:data algorithm:sender.representedObject], url.lastPathComponent]];
	}
	[self showTextResult:[lines componentsJoinedByString:@"\n"] title:sender.menu.title];
}

- (void)startMacroRecording:(id)sender {
	(void)sender; self.recordedMacro = [NSMutableArray array]; self.recordingMacro = YES; [self.editor message:SCI_STARTRECORD]; [self updateToolBar];
}
- (void)stopMacroRecording:(id)sender { (void)sender; [self.editor message:SCI_STOPRECORD]; self.recordingMacro = NO; [self updateToolBar]; }
- (void)playbackMacroOnce {
	for (NppMacMacroStep *step in self.recordedMacro) {
		sptr_t lParam = step.text ? (sptr_t)step.text.UTF8String : step.lParam;
		[ScintillaView directCall:self.editor message:step.message wParam:step.wParam lParam:lParam];
	}
}
- (void)playbackMacro:(id)sender { (void)sender; [self playbackMacroOnce]; }
- (void)runMacroMultipleTimes:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = NppL("menu.macro.runMultiple");
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)]; field.integerValue = 1;
	alert.accessoryView = field; [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:NppL("common.cancel")];
	if ([alert runModal] != NSAlertFirstButtonReturn) return;
	for (NSInteger index = 0; index < MIN(MAX(field.integerValue, 1), 10000); ++index) [self playbackMacroOnce];
}

- (void)runCommand:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = NppL("menu.run.run");
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 520, 24)];
	if (self.currentDocument.url.path) field.stringValue = [NSString stringWithFormat:@"\"%@\"", self.currentDocument.url.path];
	alert.accessoryView = field; [alert addButtonWithTitle:NppL("menu.run.execute")]; [alert addButtonWithTitle:NppL("common.cancel")];
	if ([alert runModal] != NSAlertFirstButtonReturn || field.stringValue.length == 0) return;
	NSTask *task = [[NSTask alloc] init]; task.launchPath = @"/bin/zsh"; task.arguments = @[@"-lc", field.stringValue];
	NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
	@try { [task launch]; [task waitUntilExit]; }
	@catch (NSException *exception) { [self showTextResult:exception.reason title:NppL("menu.run.run")]; return; }
	NSString *output = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
	[self appendDocumentWithText:output url:nil];
}

- (void)openPluginsFolder:(id)sender {
	(void)sender;
	NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
	NSURL *plugins = [[support URLByAppendingPathComponent:@"Notepad++Mac" isDirectory:YES] URLByAppendingPathComponent:@"Plugins" isDirectory:YES];
	[NSFileManager.defaultManager createDirectoryAtURL:plugins withIntermediateDirectories:YES attributes:nil error:nil];
	[NSWorkspace.sharedWorkspace openURL:plugins];
}

- (void)sortDocumentsUsingKey:(NSString *(^)(NppMacDocument *document))key ascending:(BOOL)ascending {
	NppMacDocument *active = self.currentDocument;
	[self.documents sortUsingComparator:^NSComparisonResult(NppMacDocument *left, NppMacDocument *right) {
		NSComparisonResult result = [key(left) localizedCaseInsensitiveCompare:key(right)];
		return ascending ? result : (NSComparisonResult)-result;
	}];
	self.currentDocumentIndex = (NSInteger)[self.documents indexOfObjectIdenticalTo:active];
	[self rebuildTabBar]; [self persistSession];
}
- (void)sortDocumentsByNameAscending:(id)sender { (void)sender; [self sortDocumentsUsingKey:^NSString *(NppMacDocument *d) { return d.url.lastPathComponent ?: @""; } ascending:YES]; }
- (void)sortDocumentsByNameDescending:(id)sender { (void)sender; [self sortDocumentsUsingKey:^NSString *(NppMacDocument *d) { return d.url.lastPathComponent ?: @""; } ascending:NO]; }
- (void)sortDocumentsByPathAscending:(id)sender { (void)sender; [self sortDocumentsUsingKey:^NSString *(NppMacDocument *d) { return d.url.path ?: @""; } ascending:YES]; }
- (void)sortDocumentsByPathDescending:(id)sender { (void)sender; [self sortDocumentsUsingKey:^NSString *(NppMacDocument *d) { return d.url.path ?: @""; } ascending:NO]; }

- (void)showDocumentList:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = NppL("menu.window.windows");
	NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 360, 26)];
	for (NppMacDocument *document in self.documents) [popup addItemWithTitle:document.url.lastPathComponent ?: NppL("common.untitled")];
	[popup selectItemAtIndex:self.currentDocumentIndex];
	alert.accessoryView = popup; [alert addButtonWithTitle:NppL("common.go")]; [alert addButtonWithTitle:NppL("common.cancel")];
	if ([alert runModal] == NSAlertFirstButtonReturn && popup.indexOfSelectedItem >= 0) [self switchToDocumentAtIndex:(NSUInteger)popup.indexOfSelectedItem];
}

- (void)openHelpURL:(NSMenuItem *)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:sender.representedObject]]; }
- (void)showCommandLineHelp:(id)sender {
	(void)sender; [self showTextResult:@"open -a Notepad++Mac --args <file>\nNotepad++Mac <file>" title:NppL("menu.help.commandLine")];
}
- (void)showDebugInfo:(id)sender {
	(void)sender;
	NSString *info = [NSString stringWithFormat:@"Notepad++Mac %@ (%@)\nmacOS %@\nArchitecture: %@\nDocuments: %lu",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
		NSProcessInfo.processInfo.operatingSystemVersionString,
#if defined(__arm64__)
		@"arm64",
#else
		@"x86_64",
#endif
		(unsigned long)self.documents.count];
	[self showTextResult:info title:NppL("menu.help.debug")];
}

- (NSArray<NppMacFindDocumentSnapshot *> *)findDocumentSnapshots {
	if (self.documents.count == 0) {
		return @[];
	}
	sptr_t originalDocument = [self.editor message:SCI_GETDOCPOINTER];
	NSMutableArray<NppMacFindDocumentSnapshot *> *snapshots = [NSMutableArray arrayWithCapacity:self.documents.count];
	self.suppressDirtyTracking = YES;
	[self.documents enumerateObjectsUsingBlock:^(NppMacDocument *document, NSUInteger index, BOOL *stop) {
		(void)stop;
		[self.editor message:SCI_SETDOCPOINTER wParam:0 lParam:document.documentPointer];
		NppMacFindDocumentSnapshot *snapshot = [[NppMacFindDocumentSnapshot alloc] init];
		snapshot.documentIndex = index;
		snapshot.displayName = document.url.lastPathComponent ?: NppL("common.untitled");
		snapshot.url = document.url;
		snapshot.text = self.editor.string ?: @"";
		[snapshots addObject:snapshot];
	}];
	[self.editor message:SCI_SETDOCPOINTER wParam:0 lParam:originalDocument];
	self.suppressDirtyTracking = NO;
	return snapshots;
}

- (void)replaceDocumentAtIndex:(NSUInteger)index withText:(NSString *)text {
	if (index >= self.documents.count) {
		return;
	}
	[self switchToDocumentAtIndex:index];
	const char *replacement = text.UTF8String;
	sptr_t length = [self.editor message:SCI_GETLENGTH];
	[self.editor message:SCI_BEGINUNDOACTION];
	[self.editor message:SCI_SETSEL wParam:0 lParam:length];
	[ScintillaView directCall:self.editor message:SCI_REPLACESEL wParam:0
		lParam:reinterpret_cast<sptr_t>(replacement)];
	[self.editor message:SCI_ENDUNDOACTION];
}

- (NppMacDocument *)currentDocument {
	if (self.currentDocumentIndex == NSNotFound ||
		(NSUInteger)self.currentDocumentIndex >= self.documents.count) {
		return nil;
	}
	return self.documents[(NSUInteger)self.currentDocumentIndex];
}

- (void)appendDocumentWithText:(NSString *)text url:(NSURL *)url {
	NppMacDocument *document = [[NppMacDocument alloc] init];
	document.identifier = NSUUID.UUID.UUIDString;
	document.encoding = NSUTF8StringEncoding;
	document.url = url;
	document.languageName = NppL("status.plainText");
	document.documentPointer = [self.editor message:SCI_CREATEDOCUMENT wParam:0 lParam:0];
	document.dirty = NO;
	[self.documents addObject:document];

	[self rebuildTabBar];
	[self switchToDocumentAtIndex:self.documents.count - 1];
	self.suppressDirtyTracking = YES;
	[self.editor setString:text ?: @""];
	[self applyLexerForURL:url];
	[self.editor message:SCI_EMPTYUNDOBUFFER];
	[self.editor message:SCI_SETSAVEPOINT];
	self.suppressDirtyTracking = NO;
	document.dirty = NO;
	document.lastKnownModificationDate = [self modificationDateForURL:url];
	document.missingOnDisk = NO;
	[self rebuildTabBar];
	[self updateWindowTitle];
}

- (void)switchToDocumentAtIndex:(NSUInteger)index {
	if (index >= self.documents.count) {
		return;
	}

	if (!self.restoringSession) {
		[self captureCurrentDocumentViewState];
	}
	self.currentDocumentIndex = (NSInteger)index;
	NppMacDocument *document = self.documents[index];
	self.suppressDirtyTracking = YES;
	[self.editor message:SCI_SETDOCPOINTER wParam:0 lParam:document.documentPointer];
	[self applyLexerForURL:document.url];
	[self restoreCurrentDocumentViewState];
	self.suppressDirtyTracking = NO;
	self.tabBar.selectedIndex = (NSInteger)index;
	[self updateWindowTitle];
	[self.window makeFirstResponder:self.editor];
	[self updateMarkdownPreview];
}

- (void)captureCurrentDocumentViewState {
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return;
	}
	document.caretPosition = [self.editor message:SCI_GETCURRENTPOS];
	document.anchorPosition = [self.editor message:SCI_GETANCHOR];
	document.firstVisibleLine = [self.editor message:SCI_GETFIRSTVISIBLELINE];
	document.horizontalOffset = [self.editor message:SCI_GETXOFFSET];
}

- (void)restoreCurrentDocumentViewState {
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return;
	}
	sptr_t length = [self.editor message:SCI_GETLENGTH];
	sptr_t anchor = MIN(MAX(document.anchorPosition, 0), length);
	sptr_t caret = MIN(MAX(document.caretPosition, 0), length);
	[self.editor message:SCI_SETSEL wParam:(uptr_t)anchor lParam:caret];
	[self.editor message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)MAX(document.firstVisibleLine, 0)];
	[self.editor message:SCI_SETXOFFSET wParam:(uptr_t)MAX(document.horizontalOffset, 0)];
}

- (void)rebuildTabBar {
	NSMutableArray<NppMacTabItem *> *items = [NSMutableArray arrayWithCapacity:self.documents.count];
	[self.documents enumerateObjectsUsingBlock:^(NppMacDocument *document, NSUInteger index, BOOL *stop) {
		(void)index;
		(void)stop;
		NSString *name = document.url.lastPathComponent ?: NppL("common.untitled");
		NppMacTabItem *item = [[NppMacTabItem alloc] init];
		item.title = name;
		item.toolTip = document.url.path ?: name;
		item.dirty = document.dirty;
		[items addObject:item];
	}];
	self.tabBar.items = items;
	if (self.currentDocumentIndex != NSNotFound) {
		self.tabBar.selectedIndex = self.currentDocumentIndex;
	}
}

- (NSData *)encodedDataForText:(NSString *)text document:(NppMacDocument *)document {
	NSData *body = [text dataUsingEncoding:document.encoding allowLossyConversion:NO];
	if (!body || !document.writeBOM) return body;
	const unsigned char *bom = nullptr;
	NSUInteger bomLength = 0;
	const unsigned char utf8BOM[] = {0xEF, 0xBB, 0xBF};
	const unsigned char utf16LEBOM[] = {0xFF, 0xFE};
	const unsigned char utf16BEBOM[] = {0xFE, 0xFF};
	if (document.encoding == NSUTF8StringEncoding) { bom = utf8BOM; bomLength = sizeof(utf8BOM); }
	else if (document.encoding == NSUTF16LittleEndianStringEncoding) { bom = utf16LEBOM; bomLength = sizeof(utf16LEBOM); }
	else if (document.encoding == NSUTF16BigEndianStringEncoding) { bom = utf16BEBOM; bomLength = sizeof(utf16BEBOM); }
	if (!bom) return body;
	NSMutableData *result = [NSMutableData dataWithBytes:bom length:bomLength];
	[result appendData:body];
	return result;
}

- (BOOL)writeCurrentDocumentToURL:(NSURL *)url {
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return NO;
	}

	NSError *error = nil;
	NSString *text = [self.editor string] ?: @"";
	NSData *data = [self encodedDataForText:text document:document];
	if (!data) {
		error = [NSError errorWithDomain:@"Notepad++Mac" code:1 userInfo:@{NSLocalizedDescriptionKey: NppL("alert.encoding.error")}];
	}
	if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
		[self showError:error message:NppL("alert.save.error")];
		return NO;
	}
	document.url = url;
	[self.editor message:SCI_SETSAVEPOINT];
	document.dirty = NO;
	[self removeSnapshotForDocument:document];
	document.lastKnownModificationDate = [self modificationDateForURL:url];
	document.missingOnDisk = NO;
	[self rebuildTabBar];
	[self updateWindowTitle];
	return YES;
}

- (BOOL)openURL:(NSURL *)url {
	NSURL *standardURL = url.URLByStandardizingPath;
	for (NSUInteger index = 0; index < self.documents.count; ++index) {
		NSURL *openURL = self.documents[index].url.URLByStandardizingPath;
		if (openURL && [openURL isEqual:standardURL]) {
			[self switchToDocumentAtIndex:index];
			return YES;
		}
	}

	NSError *error = nil;
	NSStringEncoding encoding = NSUTF8StringEncoding;
	NSData *rawData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
	const unsigned char *bytes = static_cast<const unsigned char *>(rawData.bytes);
	BOOL hasBOM = (rawData.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) ||
		(rawData.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF)));
	NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:&error];
	if (!text) {
		encoding = NSISOLatin1StringEncoding;
		text = [NSString stringWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:&error];
	}
	if (!text) {
		[self showError:error message:NppL("alert.open.error")];
		return NO;
	}

	NppMacDocument *current = self.currentDocument;
	BOOL reuseUntitled = self.documents.count == 1 && !current.url && !current.dirty &&
		[self.editor message:SCI_GETLENGTH] == 0;
	if (reuseUntitled) {
		current.url = url;
		current.encoding = encoding;
		current.writeBOM = hasBOM;
		self.suppressDirtyTracking = YES;
		[self.editor setString:text];
		[self applyLexerForURL:url];
		[self.editor message:SCI_EMPTYUNDOBUFFER];
		[self.editor message:SCI_SETSAVEPOINT];
		self.suppressDirtyTracking = NO;
		current.dirty = NO;
		current.lastKnownModificationDate = [self modificationDateForURL:url];
		current.missingOnDisk = NO;
		[self rebuildTabBar];
		[self updateWindowTitle];
	} else {
		[self appendDocumentWithText:text url:url];
		self.currentDocument.encoding = encoding;
		self.currentDocument.writeBOM = hasBOM;
	}
	return YES;
}

- (NSDate *)modificationDateForURL:(NSURL *)url {
	if (!url.isFileURL) {
		return nil;
	}
	NSDate *date = nil;
	[url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
	return date;
}

- (BOOL)reloadCurrentDocumentFromDisk {
	NppMacDocument *document = self.currentDocument;
	if (!document.url) {
		return NO;
	}
	NSError *error = nil;
	NSStringEncoding encoding = NSUTF8StringEncoding;
	NSString *text = [NSString stringWithContentsOfURL:document.url usedEncoding:&encoding error:&error];
	if (!text) {
		encoding = NSISOLatin1StringEncoding;
		text = [NSString stringWithContentsOfURL:document.url encoding:NSISOLatin1StringEncoding error:&error];
	}
	if (!text) {
		[self showError:error message:NppL("alert.reload.error")];
		return NO;
	}

	[self captureCurrentDocumentViewState];
	self.suppressDirtyTracking = YES;
	[self.editor setString:text];
	[self applyLexerForURL:document.url];
	[self.editor message:SCI_EMPTYUNDOBUFFER];
	[self.editor message:SCI_SETSAVEPOINT];
	[self restoreCurrentDocumentViewState];
	self.suppressDirtyTracking = NO;
	document.dirty = NO;
	document.encoding = encoding;
	[self removeSnapshotForDocument:document];
	document.lastKnownModificationDate = [self modificationDateForURL:document.url];
	document.missingOnDisk = NO;
	[self rebuildTabBar];
	[self updateWindowTitle];
	return YES;
}

- (void)checkForExternalFileChanges {
	if (self.checkingExternalChanges || !self.editor) {
		return;
	}
	self.checkingExternalChanges = YES;
	for (NSUInteger index = 0; index < self.documents.count; ++index) {
		NppMacDocument *document = self.documents[index];
		if (!document.url.isFileURL) {
			continue;
		}

		NSDate *diskDate = [self modificationDateForURL:document.url];
		if (!diskDate) {
			if (!document.missingOnDisk) {
				[self switchToDocumentAtIndex:index];
				document.missingOnDisk = YES;
				document.dirty = YES;
				[self scheduleSnapshotForDocument:document];
				NSAlert *alert = [[NSAlert alloc] init];
				alert.messageText = NppL("alert.removed.title");
				alert.informativeText = [NSString stringWithFormat:NppL("alert.removed.message"),
					document.url.lastPathComponent];
				[alert addButtonWithTitle:NppL("alert.removed.keep")];
				[alert addButtonWithTitle:NppL("menu.file.saveAs")];
				if ([alert runModal] == NSAlertSecondButtonReturn) {
					[self saveCurrentDocumentAs];
				}
				[self rebuildTabBar];
				[self updateWindowTitle];
			}
			continue;
		}

		BOOL changed = document.missingOnDisk ||
			(document.lastKnownModificationDate && ![document.lastKnownModificationDate isEqualToDate:diskDate]);
		if (!changed) {
			document.lastKnownModificationDate = diskDate;
			continue;
		}

		[self switchToDocumentAtIndex:index];
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NppL("alert.changed.title");
		alert.informativeText = document.dirty
			? NppL("alert.changed.dirty")
			: NppL("alert.changed.clean");
		[alert addButtonWithTitle:NppL("common.reload")];
		[alert addButtonWithTitle:NppL("alert.changed.keep")];
		if ([alert runModal] == NSAlertFirstButtonReturn) {
			[self reloadCurrentDocumentFromDisk];
		} else {
			document.lastKnownModificationDate = diskDate;
			document.missingOnDisk = NO;
			document.dirty = YES;
			[self scheduleSnapshotForDocument:document];
			[self rebuildTabBar];
			[self updateWindowTitle];
		}
	}
	self.checkingExternalChanges = NO;
}

- (BOOL)closeDocumentAtIndex:(NSUInteger)index {
	if (index >= self.documents.count || ![self confirmCloseDocumentAtIndex:index]) {
		return NO;
	}

	NppMacDocument *closingDocument = self.documents[index];
	if (self.documents.count == 1) {
		[self appendDocumentWithText:@"" url:nil];
	} else {
		NSUInteger nextIndex = index == self.documents.count - 1 ? index - 1 : index + 1;
		[self switchToDocumentAtIndex:nextIndex];
	}

	[self.documents removeObjectAtIndex:index];
	[self removeSnapshotForDocument:closingDocument];
	[self.editor message:SCI_RELEASEDOCUMENT wParam:0 lParam:closingDocument.documentPointer];
	if ((NSUInteger)self.currentDocumentIndex > index) {
		self.currentDocumentIndex--;
	}
	[self rebuildTabBar];
	[self updateWindowTitle];
	return YES;
}

- (BOOL)confirmCloseDocumentAtIndex:(NSUInteger)index {
	if (index >= self.documents.count) {
		return YES;
	}
	[self switchToDocumentAtIndex:index];
	NppMacDocument *document = self.currentDocument;
	if (!document.dirty && ![self.editor message:SCI_GETMODIFY]) {
		return YES;
	}

	NSString *name = document.url.lastPathComponent ?: NppL("common.untitled");
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:NppL("alert.saveChanges.title"), name];
	alert.informativeText = NppL("alert.saveChanges.message");
	[alert addButtonWithTitle:NppL("common.save")];
	[alert addButtonWithTitle:NppL("common.cancel")];
	[alert addButtonWithTitle:NppL("common.discard")];
	NSModalResponse response = [alert runModal];
	if (response == NSAlertFirstButtonReturn) {
		return document.url ? [self writeCurrentDocumentToURL:document.url] : [self saveCurrentDocumentAs];
	}
	if (response == NSAlertSecondButtonReturn) {
		return NO;
	}
	if (self.confirmingAllDocuments) {
		document.discardOnTermination = YES;
	} else {
		[self removeSnapshotForDocument:document];
	}
	return YES;
}

- (BOOL)confirmCloseAllDocuments {
	self.confirmingAllDocuments = YES;
	for (NSInteger index = (NSInteger)self.documents.count - 1; index >= 0; --index) {
		if (![self confirmCloseDocumentAtIndex:(NSUInteger)index]) {
			for (NppMacDocument *document in self.documents) {
				document.discardOnTermination = NO;
			}
			self.confirmingAllDocuments = NO;
			return NO;
		}
	}
	for (NppMacDocument *document in self.documents) {
		if (document.discardOnTermination) {
			[self removeSnapshotForDocument:document];
		}
	}
	self.confirmingAllDocuments = NO;
	return YES;
}

- (void)scheduleSnapshotForDocument:(NppMacDocument *)document {
	if (!document.identifier) {
		document.identifier = NSUUID.UUID.UUIDString;
	}
	[self.snapshotTimers[document.identifier] invalidate];
	__weak NppMacAppDelegate *weakSelf = self;
	__weak NppMacDocument *weakDocument = document;
	NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:NO block:^(NSTimer *firedTimer) {
		(void)firedTimer;
		NppMacAppDelegate *strongSelf = weakSelf;
		NppMacDocument *strongDocument = weakDocument;
		if (strongSelf && strongDocument) {
			[strongSelf snapshotDocument:strongDocument];
		}
	}];
	self.snapshotTimers[document.identifier] = timer;
}

- (void)snapshotDocument:(NppMacDocument *)document {
	NSUInteger targetIndex = [self.documents indexOfObjectIdenticalTo:document];
	if (targetIndex == NSNotFound || !document.dirty) {
		return;
	}
	NSUInteger originalIndex = self.currentDocumentIndex == NSNotFound ? targetIndex : (NSUInteger)self.currentDocumentIndex;
	[self.editor suspendDrawing:YES];
	if (targetIndex != originalIndex) {
		[self switchToDocumentAtIndex:targetIndex];
	}
	NSError *error = nil;
	NSURL *backupURL = [self.recoveryStore writeSnapshot:[self.editor string] ?: @""
		identifier:document.identifier
		error:&error];
	if (backupURL) {
		document.backupURL = backupURL;
	} else {
		NSLog(@"Could not write recovery snapshot: %@", error.localizedDescription);
	}
	if (targetIndex != originalIndex && originalIndex < self.documents.count) {
		[self switchToDocumentAtIndex:originalIndex];
	}
	[self.editor suspendDrawing:NO];
	[self.snapshotTimers removeObjectForKey:document.identifier];
	[self persistSession];
}

- (void)removeSnapshotForDocument:(NppMacDocument *)document {
	if (document.identifier) {
		[self.snapshotTimers[document.identifier] invalidate];
		[self.snapshotTimers removeObjectForKey:document.identifier];
	}
	[self.recoveryStore removeSnapshotAtURL:document.backupURL];
	document.backupURL = nil;
}

- (void)persistSession {
	[self captureCurrentDocumentViewState];
	NSMutableArray<NppMacSessionEntry *> *entries = [NSMutableArray array];
	NSInteger activeSavedIndex = 0;
	for (NSUInteger index = 0; index < self.documents.count; ++index) {
		NppMacDocument *document = self.documents[index];
		if ((!document.url.isFileURL && !document.backupURL.isFileURL) || document.discardOnTermination) {
			continue;
		}

		if ((NSInteger)index == self.currentDocumentIndex) {
			activeSavedIndex = (NSInteger)entries.count;
		}
		NppMacSessionEntry *entry = [[NppMacSessionEntry alloc] init];
		entry.url = document.url;
		entry.backupURL = document.backupURL;
		entry.identifier = document.identifier;
		entry.caretPosition = document.caretPosition;
		entry.anchorPosition = document.anchorPosition;
		entry.firstVisibleLine = document.firstVisibleLine;
		entry.horizontalOffset = document.horizontalOffset;
		[entries addObject:entry];
	}
	[self.sessionStore saveEntries:entries activeIndex:activeSavedIndex];
}

- (void)restoreSession {
	NppMacSession *session = [self.sessionStore loadSession];
	if (session.entries.count == 0) {
		return;
	}

	self.restoringSession = YES;
	__block NSInteger desiredDocumentIndex = NSNotFound;
	__block NSInteger fallbackDocumentIndex = NSNotFound;
	[session.entries enumerateObjectsUsingBlock:^(NppMacSessionEntry *entry, NSUInteger index, BOOL *stop) {
		(void)stop;
		NSString *backupText = nil;
		if ([entry.backupURL checkResourceIsReachableAndReturnError:nil]) {
			backupText = [self.recoveryStore readSnapshotAtURL:entry.backupURL error:nil];
		}
		BOOL originalExists = [entry.url checkResourceIsReachableAndReturnError:nil];
		BOOL opened = originalExists && [self openURL:entry.url];
		if (!opened && backupText) {
			NppMacDocument *blank = self.currentDocument;
			BOOL reuseBlank = self.documents.count == 1 && !blank.url && !blank.dirty &&
				[self.editor message:SCI_GETLENGTH] == 0;
			if (reuseBlank) {
				blank.url = entry.url;
			} else {
				[self appendDocumentWithText:@"" url:entry.url];
			}
			opened = YES;
		}
		if (!opened) {
			return;
		}

		NppMacDocument *document = self.currentDocument;
		document.identifier = entry.identifier.length > 0 ? entry.identifier : NSUUID.UUID.UUIDString;
		if (backupText) {
			self.suppressDirtyTracking = YES;
			[self.editor setString:backupText];
			[self applyLexerForURL:document.url];
			self.suppressDirtyTracking = NO;
			document.backupURL = entry.backupURL;
			document.dirty = YES;
		}
		document.caretPosition = entry.caretPosition;
		document.anchorPosition = entry.anchorPosition;
		document.firstVisibleLine = entry.firstVisibleLine;
		document.horizontalOffset = entry.horizontalOffset;
		fallbackDocumentIndex = self.currentDocumentIndex;
		if ((NSInteger)index == session.activeIndex) {
			desiredDocumentIndex = self.currentDocumentIndex;
		}
	}];

	NSInteger targetIndex = desiredDocumentIndex != NSNotFound ? desiredDocumentIndex : fallbackDocumentIndex;
	if (targetIndex != NSNotFound) {
		[self switchToDocumentAtIndex:(NSUInteger)targetIndex];
	}
	self.restoringSession = NO;
	[self rebuildTabBar];
	[self updateWindowTitle];
}

- (void)updateDirtyState {
	NppMacDocument *document = self.currentDocument;
	if (!document) {
		return;
	}
	BOOL dirty = [self.editor message:SCI_GETMODIFY] != 0;
	if (document.dirty != dirty) {
		document.dirty = dirty;
		[self rebuildTabBar];
	}
	[self updateWindowTitle];
}

- (void)updateWindowTitle {
	NppMacDocument *document = self.currentDocument;
	NSString *name = document.url.lastPathComponent ?: NppL("common.untitled");
	self.window.title = [NSString stringWithFormat:@"%@ - Notepad++Mac", name];
	self.window.documentEdited = document.dirty;
	[self updateStatusBar];
}

- (void)showError:(NSError *)error message:(NSString *)message {
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = message;
	alert.informativeText = error.localizedDescription ?: NppL("common.unknownError");
	[alert runModal];
}

- (void)updateStatusBar {
	NppMacDocument *document = self.currentDocument;
	NSString *dirtyText = document.dirty ? NppL("status.modified") : NppL("status.saved");
	NSUInteger index = self.currentDocumentIndex == NSNotFound ? 0 : (NSUInteger)self.currentDocumentIndex + 1;
	sptr_t position = [self.editor message:SCI_GETCURRENTPOS];
	sptr_t line = [self.editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)position] + 1;
	sptr_t column = [self.editor message:SCI_GETCOLUMN wParam:(uptr_t)position] + 1;
	sptr_t byteLength = [self.editor message:SCI_GETLENGTH];
	sptr_t characterCount = [self.editor message:SCI_COUNTCHARACTERS wParam:0 lParam:byteLength];
	sptr_t selectionStart = [self.editor message:SCI_GETSELECTIONSTART];
	sptr_t selectionEnd = [self.editor message:SCI_GETSELECTIONEND];
	sptr_t selectionCount = [self.editor message:SCI_COUNTCHARACTERS
		wParam:(uptr_t)MIN(selectionStart, selectionEnd)
		lParam:MAX(selectionStart, selectionEnd)];
	NSInteger eolMode = [self.editor message:SCI_GETEOLMODE];
	NSString *eolName = eolMode == SC_EOL_CRLF ? @"CRLF" : (eolMode == SC_EOL_CR ? @"CR" : @"LF");
	NSString *encodingName = @"UTF-8";
	if (document.encoding == NSISOLatin1StringEncoding) {
		encodingName = @"ISO-8859-1";
	} else if (document.encoding == NSUTF16StringEncoding || document.encoding == NSUTF16LittleEndianStringEncoding ||
		document.encoding == NSUTF16BigEndianStringEncoding) {
		encodingName = @"UTF-16";
	} else if (document.encoding != NSUTF8StringEncoding) {
		encodingName = [NSString localizedNameOfStringEncoding:document.encoding];
	}
	self.statusBar.stringValue = [NSString stringWithFormat:NppL("status.format"),
		(long)line, (long)column, (long)selectionCount, (long)characterCount, encodingName, eolName,
		document.languageName ?: NppL("status.plainText"), dirtyText,
		(unsigned long)index, (unsigned long)self.documents.count];
	[self updateToolBar];
}

- (void)updateToolBar {
	if (!self.toolBar || !self.editor) return;
	BOOL hasDocument = self.currentDocument != nil;
	BOOL readOnly = [self.editor message:SCI_GETREADONLY] != 0;
	BOOL hasSelection = [self.editor message:SCI_GETSELECTIONSTART] != [self.editor message:SCI_GETSELECTIONEND];
	BOOL anyDirty = NO;
	for (NppMacDocument *document in self.documents) anyDirty = anyDirty || document.dirty;

	[self.toolBar setButtonEnabled:hasDocument && self.currentDocument.dirty forAction:@selector(saveDocument:)];
	[self.toolBar setButtonEnabled:anyDirty forAction:@selector(saveAllDocuments:)];
	[self.toolBar setButtonEnabled:hasDocument forAction:@selector(closeDocument:)];
	[self.toolBar setButtonEnabled:hasDocument forAction:@selector(closeAllDocuments:)];
	[self.toolBar setButtonEnabled:hasDocument forAction:@selector(printDocument:)];
	[self.toolBar setButtonEnabled:hasSelection && !readOnly forAction:@selector(cut:)];
	[self.toolBar setButtonEnabled:hasSelection forAction:@selector(copy:)];
	[self.toolBar setButtonEnabled:!readOnly && [self.editor message:SCI_CANPASTE] != 0 forAction:@selector(paste:)];
	[self.toolBar setButtonEnabled:[self.editor message:SCI_CANUNDO] != 0 forAction:@selector(undo:)];
	[self.toolBar setButtonEnabled:[self.editor message:SCI_CANREDO] != 0 forAction:@selector(redo:)];
	[self.toolBar setButtonEnabled:hasDocument forAction:@selector(findText:)];
	[self.toolBar setButtonEnabled:hasDocument forAction:@selector(replaceText:)];
	[self.toolBar setButtonEnabled:!self.recordingMacro forAction:@selector(startMacroRecording:)];
	[self.toolBar setButtonEnabled:self.recordingMacro forAction:@selector(stopMacroRecording:)];
	[self.toolBar setButtonEnabled:!self.recordingMacro && self.recordedMacro.count > 0 forAction:@selector(playbackMacro:)];
	[self.toolBar setButtonEnabled:!self.recordingMacro && self.recordedMacro.count > 0 forAction:@selector(runMacroMultipleTimes:)];

	[self.toolBar setButtonOn:[self.editor message:SCI_GETWRAPMODE] != SC_WRAP_NONE forAction:@selector(toggleWordWrap:)];
	BOOL showsAllCharacters = [self.editor message:SCI_GETVIEWWS] != SCWS_INVISIBLE && [self.editor message:SCI_GETVIEWEOL] != 0;
	[self.toolBar setButtonOn:showsAllCharacters forAction:@selector(toggleAllCharacters:)];
	[self.toolBar setButtonOn:[self.editor message:SCI_GETINDENTATIONGUIDES] != SC_IV_NONE forAction:@selector(toggleIndentGuides:)];
}

- (void)applyLexerForURL:(NSURL *)url {
	NSString *displayName = NppL("status.plainText");
	const char *lexerName = nullptr;
	NppMacLanguageDefinition *catalogDefinition = nil;

	NSString *extension = url.pathExtension.lowercaseString ?: @"";
	NSString *lastPath = url.lastPathComponent.lowercaseString ?: @"";
	if ([self extension:extension isAnyOf:@[@"c", @"cc", @"cpp", @"cxx", @"h", @"hh", @"hpp", @"hxx"]]) {
		lexerName = "cpp";
		displayName = @"C/C++";
	} else if ([self extension:extension isAnyOf:@[@"m", @"mm"]]) {
		lexerName = "objc";
		displayName = @"Objective-C";
	} else if ([extension isEqualToString:@"py"] || [lastPath isEqualToString:@"sconstruct"] || [lastPath isEqualToString:@"sconscript"]) {
		lexerName = "python";
		displayName = @"Python";
	} else if ([self extension:extension isAnyOf:@[@"js", @"jsx", @"mjs", @"ts", @"tsx"]]) {
		lexerName = "cpp";
		displayName = @"JavaScript/TypeScript";
	} else if ([self extension:extension isAnyOf:@[@"json", @"jsonc", @"json5"]]) {
		lexerName = "json";
		displayName = @"JSON";
	} else if ([self extension:extension isAnyOf:@[@"html", @"htm", @"xml", @"xhtml", @"plist", @"xib"]]) {
		lexerName = "hypertext";
		displayName = @"HTML/XML";
	} else if ([self extension:extension isAnyOf:@[@"md", @"markdown", @"mdown", @"mkd", @"mkdn", @"mdx"]]) {
		lexerName = "markdown";
		displayName = @"Markdown";
	} else if ([self extension:extension isAnyOf:@[@"sh", @"bash", @"zsh", @"command"]]) {
		lexerName = "bash";
		displayName = @"Shell";
	} else if ([lastPath isEqualToString:@"makefile"] || [extension isEqualToString:@"mk"]) {
		lexerName = "makefile";
		displayName = @"Makefile";
	} else {
		catalogDefinition = [self.languageCatalog languageForFileURL:url];
		if (catalogDefinition) {
			displayName = catalogDefinition.displayName;
			lexerName = catalogDefinition.lexerName.length > 0 ? catalogDefinition.lexerName.UTF8String : nullptr;
		}
	}

	self.currentDocument.languageName = displayName;
	[self applyBaseStyles];
	[self setLexerNamed:lexerName];
	[self applyStylesForLexer:lexerName];
	[self.editor message:SCI_COLOURISE wParam:0 lParam:-1];
	[self updateStatusBar];
}

- (BOOL)extension:(NSString *)extension isAnyOf:(NSArray<NSString *> *)extensions {
	return [extensions containsObject:extension];
}

- (void)setLexerNamed:(const char *)lexerName {
	if (!lexerName || !self.lexillaHandle) {
		[self.editor setReferenceProperty:SCI_SETILEXER parameter:0 value:nullptr];
		return;
	}

	Lexilla::CreateLexerFn createLexer =
		reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(self.lexillaHandle, LEXILLA_CREATELEXER));
	if (!createLexer) {
		NSLog(@"Could not locate Lexilla CreateLexer: %s", dlerror());
		[self.editor setReferenceProperty:SCI_SETILEXER parameter:0 value:nullptr];
		return;
	}

	Scintilla::ILexer5 *lexer = createLexer(lexerName);
	if (!lexer) {
		NSLog(@"Lexilla has no lexer named %s", lexerName);
		[self.editor setReferenceProperty:SCI_SETILEXER parameter:0 value:nullptr];
		return;
	}

	[self.editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
}

- (void)applyBaseStyles {
	[self.editor suspendDrawing:YES];
	[self.editor setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:self.preferencesController.fontName];
	[self.editor setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:self.preferencesController.fontSize];
	[self.editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT fromHTML:@"#1F2328"];
	[self.editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT fromHTML:@"#FFFFFF"];
	[self.editor setGeneralProperty:SCI_STYLECLEARALL value:0];
	[self.editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER fromHTML:@"#6E7781"];
	[self.editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER fromHTML:@"#F6F8FA"];
	[self.editor suspendDrawing:NO];
}

- (void)applyStylesForLexer:(const char *)lexerName {
	if (!lexerName) {
		return;
	}

	NSString *lexer = [NSString stringWithUTF8String:lexerName];
	if ([lexer isEqualToString:@"cpp"] || [lexer isEqualToString:@"objc"]) {
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:cppKeywords];
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:1 value:cppTypeKeywords];
		[self style:SCE_C_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_C_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_C_COMMENTDOC fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_C_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_C_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_C_WORD2 fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_C_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_C_CHARACTER fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_C_PREPROCESSOR fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_C_OPERATOR fore:@"#D73A49" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"python"]) {
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:pythonKeywords];
		[self style:SCE_P_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_P_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_P_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_P_CHARACTER fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_P_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_P_CLASSNAME fore:@"#6F42C1" italic:NO bold:YES];
		[self style:SCE_P_DEFNAME fore:@"#6F42C1" italic:NO bold:YES];
		[self style:SCE_P_OPERATOR fore:@"#D73A49" italic:NO bold:NO];
		[self style:SCE_P_DECORATOR fore:@"#22863A" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"json"]) {
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:jsonKeywords];
		[self.editor setLexerProperty:@"lexer.json.allow.comments" value:@"1"];
		[self style:SCE_JSON_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_JSON_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_JSON_PROPERTYNAME fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_JSON_LINECOMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_JSON_BLOCKCOMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_JSON_OPERATOR fore:@"#D73A49" italic:NO bold:NO];
		[self style:SCE_JSON_KEYWORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_JSON_ERROR fore:@"#B31D28" italic:NO bold:YES];
	} else if ([lexer isEqualToString:@"hypertext"]) {
		[self style:SCE_H_TAG fore:@"#22863A" italic:NO bold:NO];
		[self style:SCE_H_TAGUNKNOWN fore:@"#B31D28" italic:NO bold:YES];
		[self style:SCE_H_ATTRIBUTE fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_H_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_H_DOUBLESTRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_H_SINGLESTRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_H_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_H_ENTITY fore:@"#005CC5" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"markdown"]) {
		[self style:SCE_MARKDOWN_HEADER1 fore:@"#004C99" italic:NO bold:YES];
		[self style:SCE_MARKDOWN_HEADER2 fore:@"#004C99" italic:NO bold:YES];
		[self style:SCE_MARKDOWN_HEADER3 fore:@"#004C99" italic:NO bold:YES];
		[self style:SCE_MARKDOWN_STRONG1 fore:@"#1F2328" italic:NO bold:YES];
		[self style:SCE_MARKDOWN_STRONG2 fore:@"#1F2328" italic:NO bold:YES];
		[self style:SCE_MARKDOWN_EM1 fore:@"#1F2328" italic:YES bold:NO];
		[self style:SCE_MARKDOWN_EM2 fore:@"#1F2328" italic:YES bold:NO];
		[self style:SCE_MARKDOWN_BLOCKQUOTE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_MARKDOWN_LINK fore:@"#0050A4" italic:NO bold:NO];
		[self style:SCE_MARKDOWN_CODE fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_MARKDOWN_CODE2 fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_MARKDOWN_CODEBK fore:@"#032F62" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"bash"]) {
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:bashKeywords];
		[self style:SCE_SH_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_SH_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_SH_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_SH_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_SH_CHARACTER fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_SH_OPERATOR fore:@"#D73A49" italic:NO bold:NO];
		[self style:SCE_SH_SCALAR fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_SH_PARAM fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_SH_BACKTICKS fore:@"#032F62" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"css"]) {
		[self style:SCE_CSS_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_CSS_TAG fore:@"#22863A" italic:NO bold:NO];
		[self style:SCE_CSS_CLASS fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_CSS_ID fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_CSS_DIRECTIVE fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_CSS_DOUBLESTRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_CSS_SINGLESTRING fore:@"#032F62" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"sql"]) {
		[self style:SCE_SQL_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_SQL_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_SQL_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_SQL_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_SQL_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_SQL_OPERATOR fore:@"#D73A49" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"ruby"]) {
		[self style:SCE_RB_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_RB_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_RB_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_RB_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_RB_CLASSNAME fore:@"#6F42C1" italic:NO bold:YES];
		[self style:SCE_RB_DEFNAME fore:@"#6F42C1" italic:NO bold:YES];
	} else if ([lexer isEqualToString:@"perl"]) {
		[self style:SCE_PL_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_PL_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_PL_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_PL_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_PL_SCALAR fore:@"#6F42C1" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"rust"]) {
		[self style:SCE_RUST_COMMENTBLOCK fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_RUST_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_RUST_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_RUST_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_RUST_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_RUST_MACRO fore:@"#6F42C1" italic:NO bold:YES];
	} else if ([lexer isEqualToString:@"yaml"]) {
		[self style:SCE_YAML_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_YAML_KEYWORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_YAML_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_YAML_REFERENCE fore:@"#6F42C1" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"toml"]) {
		[self style:SCE_TOML_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_TOML_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_TOML_TABLE fore:@"#6F42C1" italic:NO bold:YES];
		[self style:SCE_TOML_KEY fore:@"#22863A" italic:NO bold:NO];
		[self style:SCE_TOML_STRING_DQ fore:@"#032F62" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"lua"]) {
		[self style:SCE_LUA_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_LUA_COMMENTLINE fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_LUA_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_LUA_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_LUA_STRING fore:@"#032F62" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"powershell"]) {
		[self style:SCE_POWERSHELL_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_POWERSHELL_STRING fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_POWERSHELL_NUMBER fore:@"#005CC5" italic:NO bold:NO];
		[self style:SCE_POWERSHELL_VARIABLE fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_POWERSHELL_KEYWORD fore:@"#D73A49" italic:NO bold:YES];
	} else if ([lexer isEqualToString:@"cmake"]) {
		[self style:SCE_CMAKE_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_CMAKE_STRINGDQ fore:@"#032F62" italic:NO bold:NO];
		[self style:SCE_CMAKE_COMMANDS fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_CMAKE_VARIABLE fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_CMAKE_NUMBER fore:@"#005CC5" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"batch"]) {
		[self style:SCE_BAT_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_BAT_WORD fore:@"#D73A49" italic:NO bold:YES];
		[self style:SCE_BAT_LABEL fore:@"#6F42C1" italic:NO bold:NO];
		[self style:SCE_BAT_COMMAND fore:@"#005CC5" italic:NO bold:NO];
	} else if ([lexer isEqualToString:@"diff"]) {
		[self style:SCE_DIFF_COMMENT fore:@"#6A737D" italic:YES bold:NO];
		[self style:SCE_DIFF_HEADER fore:@"#6F42C1" italic:NO bold:YES];
		[self style:SCE_DIFF_DELETED fore:@"#B31D28" italic:NO bold:NO];
		[self style:SCE_DIFF_ADDED fore:@"#22863A" italic:NO bold:NO];
	}
}

- (void)style:(int)style fore:(NSString *)fore italic:(BOOL)italic bold:(BOOL)bold {
	[self.editor setColorProperty:SCI_STYLESETFORE parameter:style fromHTML:fore];
	[self.editor setGeneralProperty:SCI_STYLESETITALIC parameter:style value:italic ? 1 : 0];
	[self.editor setGeneralProperty:SCI_STYLESETBOLD parameter:style value:bold ? 1 : 0];
}

@end
