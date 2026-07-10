#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppMacMarkdownRenderer : NSObject
+ (NSString *)HTMLDocumentFromMarkdown:(NSString *)markdown title:(NSString *)title;
@end

NS_ASSUME_NONNULL_END
