#import <Cocoa/Cocoa.h>

@interface NppMacFileAssociationType : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *localizationKey;
@property(nonatomic, copy) NSArray<NSString *> *extensions;
@end

@interface NppMacFileAssociationManager : NSObject
@property(nonatomic, readonly, copy) NSArray<NppMacFileAssociationType *> *supportedTypes;
@property(nonatomic, readonly, copy) NSSet<NSString *> *selectedTypeIdentifiers;

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (void)applySelectedTypeIdentifiers:(NSSet<NSString *> *)identifiers
	completion:(void (^)(NSError *error))completion;
@end
