#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class NppMacFileDropView;

@protocol NppMacFileDropViewDelegate <NSObject>
- (void)fileDropView:(NppMacFileDropView *)dropView openFileURLs:(NSArray<NSURL *> *)fileURLs;
@end

@interface NppMacFileDropView : NSView
@property(nonatomic, weak) id<NppMacFileDropViewDelegate> delegate;
+ (NSArray<NSURL *> *)fileURLsFromPasteboard:(NSPasteboard *)pasteboard;
@end

NS_ASSUME_NONNULL_END
