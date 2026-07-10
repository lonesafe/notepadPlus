#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstdlib>

#import "NppMacLanguageCatalog.h"

static void require(BOOL condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		require(argc == 2, "catalog test requires langs.model.xml path");
		NSURL *xmlURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		NSError *error = nil;
		NppMacLanguageCatalog *catalog = [[NppMacLanguageCatalog alloc] initWithXMLURL:xmlURL error:&error];
		require(catalog != nil && error == nil, "Notepad++ language XML should parse");
		require(catalog.allLanguages.count > 70, "language menu should expose the complete built-in language catalog");
		NppMacLanguageDefinition *rust = [catalog languageForFileURL:[NSURL fileURLWithPath:@"/tmp/main.rs"]];
		require([rust.lexerName isEqualToString:@"rust"], "Rust should map to the Rust lexer");
		NppMacLanguageDefinition *java = [catalog languageForFileURL:[NSURL fileURLWithPath:@"/tmp/Main.java"]];
		require([java.lexerName isEqualToString:@"cpp"], "Java should map to the shared C-family lexer");
		NppMacLanguageDefinition *cmake = [catalog languageForFileURL:[NSURL fileURLWithPath:@"/tmp/CMakeLists.txt"]];
		require([cmake.lexerName isEqualToString:@"cmake"], "CMakeLists should use the CMake lexer");
		std::puts("NppMacLanguageCatalogTests passed");
	}
	return 0;
}
