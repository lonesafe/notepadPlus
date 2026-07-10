#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppMacMarkdownPreviewController : NSWindowController
@property(nonatomic, readonly, getter=isPreviewVisible) BOOL previewVisible;
- (void)showMarkdown:(NSString *)markdown baseURL:(nullable NSURL *)baseURL title:(NSString *)title;
- (void)scheduleMarkdownUpdate:(NSString *)markdown baseURL:(nullable NSURL *)baseURL title:(NSString *)title;
@end

NS_ASSUME_NONNULL_END
