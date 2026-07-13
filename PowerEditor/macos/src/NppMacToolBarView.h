#import <Cocoa/Cocoa.h>

@interface NppMacToolBarView : NSView
- (instancetype)initWithFrame:(NSRect)frame target:(id)target;
- (void)reloadLocalization;
- (void)setButtonEnabled:(BOOL)enabled forAction:(SEL)action;
- (void)setButtonOn:(BOOL)on forAction:(SEL)action;
- (NSButton *)buttonForAction:(SEL)action;
@end
