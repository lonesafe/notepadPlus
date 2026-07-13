#import <Cocoa/Cocoa.h>

@class NppMacFileAssociationManager;

@interface NppMacFileAssociationController : NSObject
- (instancetype)initWithManager:(NppMacFileAssociationManager *)manager;
- (void)showPanel;
- (void)reloadLocalization;
@end
