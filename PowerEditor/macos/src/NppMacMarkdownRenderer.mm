#import "NppMacMarkdownRenderer.h"

@implementation NppMacMarkdownRenderer

+ (NSString *)escapeHTML:(NSString *)text {
	return [[[[text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
		stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
		stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

+ (NSString *)replacePattern:(NSString *)pattern inString:(NSString *)source template:(NSString *)replacement {
	NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
	return [expression stringByReplacingMatchesInString:source options:0 range:NSMakeRange(0, source.length)
		withTemplate:replacement];
}

+ (NSString *)inlineHTML:(NSString *)source {
	NSMutableString *protectedText = [[self escapeHTML:source] mutableCopy];
	NSMutableArray<NSString *> *codeTokens = [NSMutableArray array];
	NSRegularExpression *codeExpression = [NSRegularExpression regularExpressionWithPattern:@"`([^`]+)`" options:0 error:nil];
	NSArray<NSTextCheckingResult *> *codeMatches = [codeExpression matchesInString:protectedText options:0 range:NSMakeRange(0, protectedText.length)];
	for (NSTextCheckingResult *match in codeMatches) {
		NSString *content = [protectedText substringWithRange:[match rangeAtIndex:1]];
		[codeTokens addObject:[NSString stringWithFormat:@"<code>%@</code>", content]];
	}
	for (NSInteger index = (NSInteger)codeMatches.count - 1; index >= 0; --index) {
		NSString *placeholder = [NSString stringWithFormat:@"\uE000%ld\uE001", (long)index];
		[protectedText replaceCharactersInRange:codeMatches[(NSUInteger)index].range withString:placeholder];
	}
	NSString *text = protectedText;
	text = [self replacePattern:@"!\\[([^]]*)\\]\\(([^ )]+)(?: \\\"([^\\\"]*)\\\")?\\)" inString:text
		template:@"<img src=\"$2\" alt=\"$1\" title=\"$3\">"];
	text = [self replacePattern:@"\\[([^]]+)\\]\\(([^ )]+)(?: \\\"([^\\\"]*)\\\")?\\)" inString:text
		template:@"<a href=\"$2\" title=\"$3\">$1</a>"];
	text = [self replacePattern:@"\\*\\*([^*]+)\\*\\*" inString:text template:@"<strong>$1</strong>"];
	text = [self replacePattern:@"__([^_]+)__" inString:text template:@"<strong>$1</strong>"];
	text = [self replacePattern:@"~~([^~]+)~~" inString:text template:@"<del>$1</del>"];
	text = [self replacePattern:@"(?<!\\*)\\*([^*]+)\\*(?!\\*)" inString:text template:@"<em>$1</em>"];
	text = [self replacePattern:@"(?<!_)_([^_]+)_(?!_)" inString:text template:@"<em>$1</em>"];
	for (NSUInteger index = 0; index < codeTokens.count; ++index) {
		NSString *placeholder = [NSString stringWithFormat:@"\uE000%lu\uE001", (unsigned long)index];
		text = [text stringByReplacingOccurrencesOfString:placeholder withString:codeTokens[index]];
	}
	return text;
}

+ (void)closeParagraph:(NSMutableString *)html paragraph:(NSMutableArray<NSString *> *)paragraph {
	if (paragraph.count == 0) return;
	NSMutableArray *parts = [NSMutableArray arrayWithCapacity:paragraph.count];
	for (NSString *line in paragraph) [parts addObject:[self inlineHTML:line]];
	[html appendFormat:@"<p>%@</p>\n", [parts componentsJoinedByString:@"<br>\n"]];
	[paragraph removeAllObjects];
}

+ (void)closeList:(NSMutableString *)html listType:(NSString **)listType {
	if (!*listType) return;
	[html appendFormat:@"</%@>\n", *listType];
	*listType = nil;
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown {
	NSMutableString *html = [NSMutableString string];
	NSMutableArray<NSString *> *paragraph = [NSMutableArray array];
	NSString *listType = nil;
	BOOL inCodeFence = NO;
	NSString *codeLanguage = @"";
	NSMutableString *code = [NSMutableString string];

	for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
		NSTextCheckingResult *fence = [[NSRegularExpression regularExpressionWithPattern:@"^\\s*```\\s*([A-Za-z0-9_+-]*)\\s*$"
			options:0 error:nil] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
		if (fence) {
			if (inCodeFence) {
				[html appendFormat:@"<pre><code class=\"language-%@\">%@</code></pre>\n",
					[self escapeHTML:codeLanguage], [self escapeHTML:code]];
				[code setString:@""];
				inCodeFence = NO;
			} else {
				[self closeParagraph:html paragraph:paragraph];
				[self closeList:html listType:&listType];
				NSRange languageRange = [fence rangeAtIndex:1];
				codeLanguage = languageRange.location == NSNotFound ? @"" : [line substringWithRange:languageRange];
				inCodeFence = YES;
			}
			continue;
		}
		if (inCodeFence) {
			[code appendFormat:@"%@\n", line];
			continue;
		}

		NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (trimmed.length == 0) {
			[self closeParagraph:html paragraph:paragraph];
			[self closeList:html listType:&listType];
			continue;
		}

		NSTextCheckingResult *heading = [[NSRegularExpression regularExpressionWithPattern:@"^(#{1,6})\\s+(.+?)\\s*#*$"
			options:0 error:nil] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
		if (heading) {
			[self closeParagraph:html paragraph:paragraph];
			[self closeList:html listType:&listType];
			NSUInteger level = [heading rangeAtIndex:1].length;
			NSString *content = [line substringWithRange:[heading rangeAtIndex:2]];
			[html appendFormat:@"<h%lu>%@</h%lu>\n", (unsigned long)level, [self inlineHTML:content], (unsigned long)level];
			continue;
		}

		if ([trimmed rangeOfString:@"^([-*_])(?:\\s*\\1){2,}$" options:NSRegularExpressionSearch].location != NSNotFound) {
			[self closeParagraph:html paragraph:paragraph];
			[self closeList:html listType:&listType];
			[html appendString:@"<hr>\n"];
			continue;
		}

		NSTextCheckingResult *unordered = [[NSRegularExpression regularExpressionWithPattern:@"^\\s*[-+*]\\s+(.+)$"
			options:0 error:nil] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
		NSTextCheckingResult *ordered = [[NSRegularExpression regularExpressionWithPattern:@"^\\s*\\d+[.)]\\s+(.+)$"
			options:0 error:nil] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
		if (unordered || ordered) {
			[self closeParagraph:html paragraph:paragraph];
			NSString *wantedType = unordered ? @"ul" : @"ol";
			if (![listType isEqualToString:wantedType]) {
				[self closeList:html listType:&listType];
				listType = wantedType;
				[html appendFormat:@"<%@>\n", listType];
			}
			NSTextCheckingResult *match = unordered ?: ordered;
			[html appendFormat:@"<li>%@</li>\n", [self inlineHTML:[line substringWithRange:[match rangeAtIndex:1]]]];
			continue;
		}

		if ([trimmed hasPrefix:@">"]) {
			[self closeParagraph:html paragraph:paragraph];
			[self closeList:html listType:&listType];
			NSString *quote = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			[html appendFormat:@"<blockquote>%@</blockquote>\n", [self inlineHTML:quote]];
			continue;
		}

		[self closeList:html listType:&listType];
		[paragraph addObject:line];
	}
	if (inCodeFence) [html appendFormat:@"<pre><code>%@</code></pre>\n", [self escapeHTML:code]];
	[self closeParagraph:html paragraph:paragraph];
	[self closeList:html listType:&listType];
	return html;
}

+ (NSString *)HTMLDocumentFromMarkdown:(NSString *)markdown title:(NSString *)title {
	NSString *body = [self bodyHTMLFromMarkdown:markdown ?: @""];
	return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\">"
		"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
		"<title>%@</title><style>"
		":root{color-scheme:light dark}body{box-sizing:border-box;max-width:920px;margin:0 auto;padding:32px 40px;"
		"font:16px/1.65 -apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif;color:#1f2328;background:#fff}"
		"h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.35em 0 .55em;font-weight:650}h1,h2{border-bottom:1px solid #d0d7de;padding-bottom:.3em}"
		"a{color:#0050a4}img{max-width:100%%}pre{overflow:auto;padding:16px;background:#f6f8fa;border:1px solid #d8dee4;border-radius:6px}"
		"code{font:14px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;background:#eff1f3;padding:.16em .34em;border-radius:4px}"
		"pre code{background:transparent;padding:0}blockquote{margin:0;padding:0 1em;color:#57606a;border-left:4px solid #d0d7de}"
		"table{border-collapse:collapse}th,td{padding:6px 13px;border:1px solid #d0d7de}hr{border:0;border-top:1px solid #d0d7de}"
		"@media(prefers-color-scheme:dark){body{color:#e6edf3;background:#0d1117}a{color:#58a6ff}h1,h2{border-color:#30363d}"
		"pre,code{background:#161b22;border-color:#30363d}blockquote{color:#8b949e;border-color:#3b434b}}"
		"@media(max-width:640px){body{padding:20px}}</style></head><body>%@</body></html>",
		[self escapeHTML:title ?: @"Markdown"], body];
}

@end
