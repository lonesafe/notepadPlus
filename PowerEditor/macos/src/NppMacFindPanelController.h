#import <Cocoa/Cocoa.h>

@class ScintillaView;

@interface NppMacFindDocumentSnapshot : NSObject
@property(nonatomic) NSUInteger documentIndex;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, copy) NSString *text;
@end

@interface NppMacFindPanelController : NSObject

@property(nonatomic, copy) NSArray<NppMacFindDocumentSnapshot *> *(^openDocumentsProvider)(void);
@property(nonatomic, copy) void (^replaceOpenDocumentHandler)(NSUInteger documentIndex, NSString *text);

- (instancetype)initWithEditor:(ScintillaView *)editor ownerWindow:(NSWindow *)ownerWindow;
- (void)showFindPanel;
- (void)showReplacePanel;
- (void)showFindInFilesPanel;
- (void)showMarkPanel;
- (void)findNext;
- (void)findPrevious;
- (void)replaceCurrent;
- (void)replaceAll;
- (NSInteger)countAll;
- (NSInteger)markAll;
- (void)clearAllMarks;
- (void)reloadLocalization;

@end
