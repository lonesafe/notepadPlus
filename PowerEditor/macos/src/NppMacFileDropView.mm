#import "NppMacFileDropView.h"

@interface NppMacFileDropView ()
@property(nonatomic) BOOL fileDragActive;
@end

@implementation NppMacFileDropView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (!self) return nil;
	[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	return self;
}

+ (NSArray<NSURL *> *)fileURLsFromPasteboard:(NSPasteboard *)pasteboard {
	NSDictionary *options = @{
		NSPasteboardURLReadingFileURLsOnlyKey: @YES,
		NSPasteboardURLReadingContentsConformToTypesKey: @[@"public.data", @"public.text", @"public.source-code"]
	};
	NSArray<NSURL *> *objects = [pasteboard readObjectsForClasses:@[NSURL.class] options:options] ?: @[];
	NSMutableArray<NSURL *> *files = [NSMutableArray array];
	for (NSURL *url in objects) {
		NSNumber *directory = nil;
		[url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
		if (url.isFileURL && !directory.boolValue) [files addObject:url.URLByStandardizingPath];
	}
	return files;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	BOOL acceptsFiles = [NppMacFileDropView fileURLsFromPasteboard:sender.draggingPasteboard].count > 0;
	self.fileDragActive = acceptsFiles;
	self.needsDisplay = YES;
	return acceptsFiles ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	return [NppMacFileDropView fileURLsFromPasteboard:sender.draggingPasteboard].count > 0 ?
		NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(nullable id<NSDraggingInfo>)sender {
	(void)sender;
	self.fileDragActive = NO;
	self.needsDisplay = YES;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	return [NppMacFileDropView fileURLsFromPasteboard:sender.draggingPasteboard].count > 0;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSArray<NSURL *> *fileURLs = [NppMacFileDropView fileURLsFromPasteboard:sender.draggingPasteboard];
	self.fileDragActive = NO;
	self.needsDisplay = YES;
	if (fileURLs.count == 0) return NO;
	[self.delegate fileDropView:self openFileURLs:fileURLs];
	return YES;
}

- (void)concludeDragOperation:(nullable id<NSDraggingInfo>)sender {
	(void)sender;
	self.fileDragActive = NO;
	self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	if (!self.fileDragActive) return;
	NSRect outline = NSInsetRect(self.bounds, 5, 5);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outline xRadius:6 yRadius:6];
	path.lineWidth = 3;
	[NSColor.selectedControlColor setStroke];
	[path stroke];
}

@end
