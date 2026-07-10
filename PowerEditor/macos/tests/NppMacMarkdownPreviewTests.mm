#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacMarkdownPreviewController.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

static void runUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && [deadline timeIntervalSinceNow] > 0) {
		[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	}
}

int main() {
	@autoreleasepool {
		[NSApplication sharedApplication];
		NppMacMarkdownPreviewController *controller = [[NppMacMarkdownPreviewController alloc] init];
		[controller showMarkdown:@"# Live Preview\n\nOpen the [manual](https://example.com)."
			baseURL:nil title:@"Preview Test"];
		require(controller.previewVisible, "preview window should become visible");
		WKWebView *webView = [controller valueForKey:@"webView"];
		runUntil(^BOOL { return !webView.loading; }, 8.0);
		require(!webView.loading, "WebKit should finish loading generated Markdown HTML");

		__block NSString *bodyText = nil;
		[webView evaluateJavaScript:@"document.body.innerText" completionHandler:^(id result, NSError *error) {
			if (!error && [result isKindOfClass:NSString.class]) bodyText = result;
		}];
		runUntil(^BOOL { return bodyText != nil; }, 4.0);
		require([bodyText containsString:@"Live Preview"] && [bodyText containsString:@"Open the manual"],
			"WebKit DOM should contain rendered Markdown content");
		[controller.window orderOut:nil];
		std::puts("NppMacMarkdownPreviewTests passed");
	}
	return 0;
}
