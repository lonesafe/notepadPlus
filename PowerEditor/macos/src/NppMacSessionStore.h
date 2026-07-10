#import <Foundation/Foundation.h>

@interface NppMacSessionEntry : NSObject
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) NSURL *backupURL;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) NSInteger caretPosition;
@property(nonatomic) NSInteger anchorPosition;
@property(nonatomic) NSInteger firstVisibleLine;
@property(nonatomic) NSInteger horizontalOffset;
@end

@interface NppMacSession : NSObject
@property(nonatomic, copy) NSArray<NppMacSessionEntry *> *entries;
@property(nonatomic) NSInteger activeIndex;
@end

@interface NppMacSessionStore : NSObject

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (NppMacSession *)loadSession;
- (void)saveEntries:(NSArray<NppMacSessionEntry *> *)entries activeIndex:(NSInteger)activeIndex;

@end
