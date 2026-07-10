#import "NppMacCodeFormatter.h"

static NSString *const NppMacFormatterErrorDomain = @"NppMacFormatterError";

@implementation NppMacCodeFormatter

+ (NSString *)languageIdentifierForURL:(NSURL *)url languageName:(NSString *)languageName {
	NSString *extension = url.pathExtension.lowercaseString ?: @"";
	NSDictionary<NSString *, NSString *> *extensions = @{
		@"json": @"json", @"jsonc": @"json", @"json5": @"json",
		@"js": @"javascript", @"jsx": @"javascript", @"mjs": @"javascript", @"cjs": @"javascript",
		@"html": @"html", @"htm": @"html", @"xhtml": @"html",
		@"java": @"java",
		@"c": @"c", @"h": @"c", @"cc": @"cpp", @"cpp": @"cpp", @"cxx": @"cpp",
		@"hh": @"cpp", @"hpp": @"cpp", @"hxx": @"cpp", @"m": @"cpp", @"mm": @"cpp",
		@"cs": @"csharp", @"go": @"go", @"py": @"python", @"pyw": @"python"
	};
	NSString *identifier = extensions[extension];
	if (identifier) return identifier;

	NSString *name = languageName.lowercaseString ?: @"";
	if ([name containsString:@"json"]) return @"json";
	if ([name containsString:@"javascript"] || [name containsString:@"typescript"]) return @"javascript";
	if ([name containsString:@"html"]) return @"html";
	if ([name isEqualToString:@"java"]) return @"java";
	if ([name isEqualToString:@"c#"] || [name containsString:@"csharp"]) return @"csharp";
	if ([name isEqualToString:@"c"] || [name isEqualToString:@"c/c++"]) return @"c";
	if ([name isEqualToString:@"c++"] || [name containsString:@"objective-c"]) return @"cpp";
	if ([name isEqualToString:@"go"]) return @"go";
	if ([name containsString:@"python"]) return @"python";
	return nil;
}

+ (BOOL)supportsLanguageIdentifier:(NSString *)languageIdentifier {
	return [@[@"json", @"javascript", @"html", @"java", @"c", @"cpp", @"csharp", @"go", @"python"]
		containsObject:languageIdentifier ?: @""];
}

+ (NSString *)formatText:(NSString *)text
	languageIdentifier:(NSString *)languageIdentifier
	fileURL:(NSURL *)fileURL
	error:(NSError **)error {
	if ([languageIdentifier isEqualToString:@"json"]) {
		return [self formatJSON:text error:error];
	}
	if ([languageIdentifier isEqualToString:@"html"]) {
		NSString *tidy = [self executableNamed:@"tidy" candidates:@[@"/usr/bin/tidy"]];
		if (tidy) {
			NSString *result = [self runExecutable:tidy arguments:@[@"-quiet", @"-indent", @"-wrap", @"0",
				@"--tidy-mark", @"no", @"--show-warnings", @"no", @"--force-output", @"yes"] input:text
				acceptedExitCodes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] error:nil];
			if (result.length > 0) return result;
		}
		return [self formatBraceLanguage:text];
	}
	if ([languageIdentifier isEqualToString:@"go"]) {
		NSString *gofmt = [self executableNamed:@"gofmt" candidates:@[@"/usr/local/go/bin/gofmt", @"/opt/homebrew/bin/gofmt"]];
		if (gofmt) {
			NSString *result = [self runExecutable:gofmt arguments:@[] input:text
				acceptedExitCodes:[NSIndexSet indexSetWithIndex:0] error:nil];
			if (result) return result;
		}
		return [self formatBraceLanguage:text];
	}
	if ([languageIdentifier isEqualToString:@"python"]) {
		NSString *black = [self executableNamed:@"black" candidates:@[@"/opt/homebrew/bin/black", @"/usr/local/bin/black"]];
		if (black) {
			NSString *result = [self runExecutable:black arguments:@[@"--quiet", @"-"] input:text
				acceptedExitCodes:[NSIndexSet indexSetWithIndex:0] error:nil];
			if (result) return result;
		}
		return [self formatPythonConservatively:text];
	}

	NSDictionary *assumedExtensions = @{
		@"javascript": @"js", @"java": @"java", @"c": @"c", @"cpp": @"cpp", @"csharp": @"cs"
	};
	if (assumedExtensions[languageIdentifier]) {
		NSString *clangFormat = [self clangFormatExecutable];
		if (clangFormat) {
			NSString *filename = fileURL.lastPathComponent ?: [@"document." stringByAppendingString:assumedExtensions[languageIdentifier]];
			NSArray *arguments = @[
				[@"--assume-filename=" stringByAppendingString:filename],
				@"--style={BasedOnStyle: LLVM, IndentWidth: 4, TabWidth: 4, UseTab: Never, ColumnLimit: 100}"
			];
			NSString *result = [self runExecutable:clangFormat arguments:arguments input:text
				acceptedExitCodes:[NSIndexSet indexSetWithIndex:0] error:nil];
			if (result) return result;
		}
		return [self formatBraceLanguage:text];
	}

	if (error) {
		*error = [NSError errorWithDomain:NppMacFormatterErrorDomain code:1
			userInfo:@{NSLocalizedDescriptionKey: @"The current language does not have a formatter."}];
	}
	return nil;
}

+ (NSString *)formatJSON:(NSString *)text error:(NSError **)error {
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:error] : nil;
	if (!object) return nil;
	NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
	if (@available(macOS 10.13, *)) options |= NSJSONWritingSortedKeys;
	NSData *formatted = [NSJSONSerialization dataWithJSONObject:object options:options error:error];
	if (!formatted) return nil;
	NSString *result = [[NSString alloc] initWithData:formatted encoding:NSUTF8StringEncoding];
	return result ? [result stringByAppendingString:@"\n"] : nil;
}

+ (NSString *)clangFormatExecutable {
	NSString *direct = [self executableNamed:@"clang-format" candidates:@[
		@"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format",
		@"/opt/homebrew/bin/clang-format", @"/usr/local/bin/clang-format"
	]];
	if (direct) return direct;
	return nil;
}

+ (NSString *)executableNamed:(NSString *)name candidates:(NSArray<NSString *> *)candidates {
	NSFileManager *manager = NSFileManager.defaultManager;
	for (NSString *candidate in candidates) {
		if ([manager isExecutableFileAtPath:candidate]) return candidate;
	}
	for (NSString *directory in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"]) {
		NSString *candidate = [directory stringByAppendingPathComponent:name];
		if ([manager isExecutableFileAtPath:candidate]) return candidate;
	}
	return nil;
}

+ (NSString *)runExecutable:(NSString *)executable
	arguments:(NSArray<NSString *> *)arguments
	input:(NSString *)input
	acceptedExitCodes:(NSIndexSet *)acceptedExitCodes
	error:(NSError **)error {
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	NSFileManager *manager = NSFileManager.defaultManager;
	if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
	NSString *inputPath = [directory stringByAppendingPathComponent:@"input.txt"];
	NSString *outputPath = [directory stringByAppendingPathComponent:@"output.txt"];
	NSString *errorPath = [directory stringByAppendingPathComponent:@"error.txt"];
	[input writeToFile:inputPath atomically:YES encoding:NSUTF8StringEncoding error:error];
	[manager createFileAtPath:outputPath contents:nil attributes:nil];
	[manager createFileAtPath:errorPath contents:nil attributes:nil];

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = executable;
	task.arguments = arguments;
	task.standardInput = [NSFileHandle fileHandleForReadingAtPath:inputPath];
	task.standardOutput = [NSFileHandle fileHandleForWritingAtPath:outputPath];
	task.standardError = [NSFileHandle fileHandleForWritingAtPath:errorPath];
	@try {
		[task launch];
		[task waitUntilExit];
	} @catch (NSException *exception) {
		if (error) *error = [NSError errorWithDomain:NppMacFormatterErrorDomain code:2
			userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Could not launch the formatter."}];
		[manager removeItemAtPath:directory error:nil];
		return nil;
	}
	NSData *outputData = [NSData dataWithContentsOfFile:outputPath];
	NSData *errorData = [NSData dataWithContentsOfFile:errorPath];
	NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
	NSString *diagnostic = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
	BOOL accepted = [acceptedExitCodes containsIndex:(NSUInteger)task.terminationStatus];
	[manager removeItemAtPath:directory error:nil];
	if (!accepted) {
		if (error) *error = [NSError errorWithDomain:NppMacFormatterErrorDomain code:task.terminationStatus
			userInfo:@{NSLocalizedDescriptionKey: diagnostic.length ? diagnostic : @"The formatter rejected the document."}];
		return nil;
	}
	return output;
}

+ (NSString *)formatPythonConservatively:(NSString *)text {
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
		NSUInteger spaces = 0;
		for (NSUInteger index = 0; index < line.length; ++index) {
			unichar character = [line characterAtIndex:index];
			if (character == ' ') spaces++;
			else if (character == '\t') spaces += 4 - (spaces % 4);
			else break;
		}
		NSString *content = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		if (content.length == 0) {
			[result addObject:@""];
			continue;
		}
		NSUInteger level = (spaces + 3) / 4;
		NSString *indent = [@"" stringByPaddingToLength:level * 4 withString:@" " startingAtIndex:0];
		[result addObject:[indent stringByAppendingString:content]];
	}
	while (result.count > 1 && result.lastObject.length == 0) [result removeLastObject];
	return [[result componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

+ (NSString *)formatBraceLanguage:(NSString *)text {
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	NSInteger indentation = 0;
	BOOL inBlockComment = NO;
	for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
		NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		if (line.length == 0) {
			[result addObject:@""];
			continue;
		}
		if ([line hasPrefix:@"}"] || [line hasPrefix:@"]"] || [line hasPrefix:@")"]) indentation = MAX(indentation - 1, 0);
		NSString *prefix = [line hasPrefix:@"#"] ? @"" : [@"" stringByPaddingToLength:(NSUInteger)indentation * 4 withString:@" " startingAtIndex:0];
		[result addObject:[prefix stringByAppendingString:line]];

		NSInteger delta = 0;
		BOOL inString = NO;
		unichar quote = 0;
		for (NSUInteger index = 0; index < line.length; ++index) {
			unichar character = [line characterAtIndex:index];
			unichar next = index + 1 < line.length ? [line characterAtIndex:index + 1] : 0;
			if (inBlockComment) {
				if (character == '*' && next == '/') { inBlockComment = NO; index++; }
				continue;
			}
			if (!inString && character == '/' && next == '*') { inBlockComment = YES; index++; continue; }
			if (!inString && character == '/' && next == '/') break;
			if ((character == '"' || character == '\'') && (index == 0 || [line characterAtIndex:index - 1] != '\\')) {
				if (!inString) { inString = YES; quote = character; }
				else if (quote == character) inString = NO;
				continue;
			}
			if (inString) continue;
			if (character == '{' || character == '[' || character == '(') delta++;
			else if (character == '}' || character == ']' || character == ')') delta--;
		}
		if ([line hasPrefix:@"}"] || [line hasPrefix:@"]"] || [line hasPrefix:@")"]) delta++;
		indentation = MAX(indentation + delta, 0);
	}
	while (result.count > 1 && result.lastObject.length == 0) [result removeLastObject];
	return [[result componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

@end
