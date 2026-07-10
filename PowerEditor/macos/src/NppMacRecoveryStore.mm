#import "NppMacRecoveryStore.h"

@interface NppMacRecoveryStore ()
@property(nonatomic, strong) NSURL *directoryURL;
@end

@implementation NppMacRecoveryStore

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
	self = [super init];
	if (self) {
		_directoryURL = directoryURL;
	}
	return self;
}

- (NSURL *)writeSnapshot:(NSString *)text identifier:(NSString *)identifier error:(NSError **)error {
	if (![[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL
		withIntermediateDirectories:YES
		attributes:nil
		error:error]) {
		return nil;
	}
	NSString *safeIdentifier = identifier.length > 0 ? identifier : NSUUID.UUID.UUIDString;
	NSURL *url = [self.directoryURL URLByAppendingPathComponent:
		[safeIdentifier stringByAppendingPathExtension:@"snapshot"]];
	return [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error] ? url : nil;
}

- (NSString *)readSnapshotAtURL:(NSURL *)url error:(NSError **)error {
	return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
}

- (void)removeSnapshotAtURL:(NSURL *)url {
	if (url) {
		[[NSFileManager defaultManager] removeItemAtURL:url error:nil];
	}
}

@end
