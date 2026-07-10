#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacMarkdownRenderer.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		NSString *markdown = @"# Heading\n\nA **strong** [link](https://example.com), ~~old~~ text, and `*literal*`.\n\n- one\n- two\n\n```js\nconst x = 1 < 2;\n```\n";
		NSString *html = [NppMacMarkdownRenderer HTMLDocumentFromMarkdown:markdown title:@"Preview"];
		require([html containsString:@"<h1>Heading</h1>"], "headings should render");
		require([html containsString:@"<strong>strong</strong>"], "strong emphasis should render");
		require([html containsString:@"<del>old</del>"] && [html containsString:@"<code>*literal*</code>"],
			"strikethrough should render without applying emphasis inside inline code");
		require([html containsString:@"href=\"https://example.com\""], "links should render");
		require([html containsString:@"<ul>"] && [html containsString:@"<li>two</li>"], "lists should render");
		require([html containsString:@"language-js"] && [html containsString:@"1 &lt; 2"], "fenced code should render safely");
		require(![html containsString:@"const x = 1 < 2"], "raw markup must not leak into preview HTML");
		std::puts("NppMacMarkdownRendererTests passed");
	}
	return 0;
}
