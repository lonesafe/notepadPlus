#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>

#include "ILexer.h"
#include "Lexilla.h"

static void require(bool condition, const char *message) {
	if (!condition) {
		std::fprintf(stderr, "FAIL: %s\n", message);
		std::exit(1);
	}
}

int main(int argc, char **argv) {
	require(argc == 2, "Lexilla test requires a dylib path");
	void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	require(library != nullptr, dlerror());
	auto createLexer = reinterpret_cast<Lexilla::CreateLexerFn>(dlsym(library, LEXILLA_CREATELEXER));
	require(createLexer != nullptr, "CreateLexer should be exported");
	const char *lexerNames[] = {"cpp", "rust", "yaml", "toml", "user"};
	for (const char *name : lexerNames) {
		Scintilla::ILexer5 *lexer = createLexer(name);
		require(lexer != nullptr, name);
		lexer->Release();
	}
	dlclose(library);
	std::puts("NppMacLexillaTests passed");
	return 0;
}
