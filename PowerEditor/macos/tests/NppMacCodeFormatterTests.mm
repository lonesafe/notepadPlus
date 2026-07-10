#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacCodeFormatter.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main() {
	@autoreleasepool {
		NSDictionary *extensions = @{
			@"data.json": @"json", @"app.js": @"javascript", @"index.html": @"html", @"Main.java": @"java",
			@"main.c": @"c", @"main.cpp": @"cpp", @"Program.cs": @"csharp", @"main.go": @"go", @"app.py": @"python"
		};
		for (NSString *filename in extensions) {
			NSString *language = [NppMacCodeFormatter languageIdentifierForURL:[NSURL fileURLWithPath:filename] languageName:nil];
			require([language isEqualToString:extensions[filename]], "all requested extensions should resolve to a formatter");
			require([NppMacCodeFormatter supportsLanguageIdentifier:language], "resolved languages should be supported");
		}

		NSError *error = nil;
		NSString *json = [NppMacCodeFormatter formatText:@"{\"z\":1,\"a\":[true,false]}"
			languageIdentifier:@"json" fileURL:nil error:&error];
		require(json != nil && error == nil, "valid JSON should format without an error");
		require([json containsString:@"\n  \"a\""] && [json hasSuffix:@"\n"], "JSON should be indented and newline terminated");

		NSString *python = [NppMacCodeFormatter formatText:@"def run():  \n\tprint('ok')\t\n"
			languageIdentifier:@"python" fileURL:nil error:&error];
		require([python isEqualToString:@"def run():\n    print('ok')\n"], "Python fallback should normalize indentation and trailing whitespace");

		NSDictionary *formatSamples = @{
			@"javascript": @"function run(){console.log('ok');}",
			@"html": @"<main><h1>Title</h1><p>Text</p></main>",
			@"java": @"class Main{public static void main(String[] args){System.out.println(1);}}",
			@"c": @"int main(){return 0;}",
			@"cpp": @"class Value{public:int get(){return 1;}};",
			@"csharp": @"class Main{static void Run(){System.Console.WriteLine(1);}}",
			@"go": @"package main\nfunc main(){\nprintln(1)\n}"
		};
		for (NSString *language in formatSamples) {
			error = nil;
			NSString *formatted = [NppMacCodeFormatter formatText:formatSamples[language]
				languageIdentifier:language fileURL:nil error:&error];
			require(formatted.length > 0 && error == nil, "every requested programming language should produce formatted output");
			require(![formatted isEqualToString:formatSamples[language]], "formatting should normalize the source layout");
		}
		std::puts("NppMacCodeFormatterTests passed");
	}
	return 0;
}
