#import "NppMacMarkdownPreviewController.h"

#import <WebKit/WebKit.h>

#import "NppMacMarkdownRenderer.h"

@interface NppMacMarkdownPreviewController () <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSTimer *updateTimer;
@property(nonatomic, copy) NSString *pendingMarkdown;
@property(nonatomic, strong) NSURL *pendingBaseURL;
@property(nonatomic, copy) NSString *pendingTitle;
@end

@implementation NppMacMarkdownPreviewController

- (instancetype)init {
	NSRect frame = NSMakeRect(0, 0, 760, 760);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
		backing:NSBackingStoreBuffered defer:NO];
	self = [super initWithWindow:window];
	if (!self) return nil;
	window.minSize = NSMakeSize(420, 320);
	WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
	_webView = [[WKWebView alloc] initWithFrame:window.contentView.bounds configuration:configuration];
	_webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_webView.navigationDelegate = self;
	[window.contentView addSubview:_webView];
	return self;
}

- (BOOL)isPreviewVisible {
	return self.window.isVisible;
}

- (void)showMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL title:(NSString *)title {
	[self.updateTimer invalidate];
	self.updateTimer = nil;
	self.window.title = title;
	NSString *html = [NppMacMarkdownRenderer HTMLDocumentFromMarkdown:markdown title:title];
	[self.webView loadHTMLString:html baseURL:baseURL];
	[self showWindow:nil];
	[self.window makeKeyAndOrderFront:nil];
}

- (void)scheduleMarkdownUpdate:(NSString *)markdown baseURL:(NSURL *)baseURL title:(NSString *)title {
	if (!self.previewVisible) return;
	self.pendingMarkdown = markdown;
	self.pendingBaseURL = baseURL;
	self.pendingTitle = title;
	[self.updateTimer invalidate];
	self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.18 target:self selector:@selector(applyPendingUpdate:)
		userInfo:nil repeats:NO];
}

- (void)applyPendingUpdate:(NSTimer *)timer {
	(void)timer;
	self.window.title = self.pendingTitle;
	NSString *html = [NppMacMarkdownRenderer HTMLDocumentFromMarkdown:self.pendingMarkdown title:self.pendingTitle];
	[self.webView loadHTMLString:html baseURL:self.pendingBaseURL];
	self.updateTimer = nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
	decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	(void)webView;
	NSURL *url = navigationAction.request.URL;
	if (navigationAction.navigationType == WKNavigationTypeLinkActivated && url && !url.isFileURL) {
		[NSWorkspace.sharedWorkspace openURL:url];
		decisionHandler(WKNavigationActionPolicyCancel);
		return;
	}
	decisionHandler(WKNavigationActionPolicyAllow);
}

@end
