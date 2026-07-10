#import <Foundation/Foundation.h>

@interface NppMacRecoveryStore : NSObject

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL;
- (NSURL *)writeSnapshot:(NSString *)text identifier:(NSString *)identifier error:(NSError **)error;
- (NSString *)readSnapshotAtURL:(NSURL *)url error:(NSError **)error;
- (void)removeSnapshotAtURL:(NSURL *)url;

@end
