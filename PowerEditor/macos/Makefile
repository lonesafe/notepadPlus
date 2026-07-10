APP_NAME := Notepad++Mac
CONFIGURATION ?= Release
ARCHS ?= arm64 x86_64
ARCH_FLAGS := $(foreach arch,$(ARCHS),-arch $(arch))

ROOT_DIR := ../..
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
FRAMEWORKS_DIR := $(CONTENTS_DIR)/Frameworks
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

SCINTILLA_PROJECT := $(ROOT_DIR)/scintilla/cocoa/Scintilla/Scintilla.xcodeproj
SCINTILLA_DERIVED := $(BUILD_DIR)/scintilla-derived
SCINTILLA_PRODUCTS := $(SCINTILLA_DERIVED)/Build/Products/$(CONFIGURATION)
SCINTILLA_FRAMEWORK := $(SCINTILLA_PRODUCTS)/Scintilla.framework

LEXILLA_SRC_DIR := $(ROOT_DIR)/lexilla/src
LEXILLA_LEXLIB_DIR := $(ROOT_DIR)/lexilla/lexlib
LEXILLA_LEXERS_DIR := $(ROOT_DIR)/lexilla/lexers
LEXILLA_OBJ_DIR := $(BUILD_DIR)/lexilla-obj
LEXILLA_DYLIB := $(BUILD_DIR)/liblexilla.dylib
LEXILLA_LEXLIB_OBJS := Accessor.o CharacterCategory.o CharacterSet.o DefaultLexer.o InList.o \
	LexAccessor.o LexerBase.o LexerModule.o LexerSimple.o PropSetSimple.o StyleContext.o WordList.o
LEXILLA_LEXER_SOURCES := $(notdir $(wildcard $(LEXILLA_LEXERS_DIR)/Lex*.cxx))
LEXILLA_OBJS := $(addprefix $(LEXILLA_OBJ_DIR)/,Lexilla.o $(LEXILLA_LEXLIB_OBJS) \
	$(LEXILLA_LEXER_SOURCES:.cxx=.o))

SRC := src/main.mm src/NppMacAppDelegate.mm src/NppMacCodeFormatter.mm src/NppMacFileDropView.mm src/NppMacFindPanelController.mm \
	src/NppMacLanguageCatalog.mm src/NppMacLocalization.mm src/NppMacMarkdownPreviewController.mm \
	src/NppMacMarkdownRenderer.mm src/NppMacPreferencesController.mm src/NppMacRecoveryStore.mm \
	src/NppMacSessionStore.mm src/NppMacTabBarView.mm
BIN := $(MACOS_DIR)/$(APP_NAME)
FIND_TEST_BIN := $(BUILD_DIR)/tests/NppMacFindPanelTests
SESSION_TEST_BIN := $(BUILD_DIR)/tests/NppMacSessionStoreTests
SESSION_RESTORE_TEST_BIN := $(BUILD_DIR)/tests/NppMacSessionRestoreTests
PREFERENCES_TEST_BIN := $(BUILD_DIR)/tests/NppMacPreferencesTests
RECOVERY_TEST_BIN := $(BUILD_DIR)/tests/NppMacRecoveryStoreTests
LANGUAGE_TEST_BIN := $(BUILD_DIR)/tests/NppMacLanguageCatalogTests
LEXILLA_TEST_BIN := $(BUILD_DIR)/tests/NppMacLexillaTests
TAB_BAR_TEST_BIN := $(BUILD_DIR)/tests/NppMacTabBarTests
LOCALIZATION_TEST_BIN := $(BUILD_DIR)/tests/NppMacLocalizationTests
FORMATTER_TEST_BIN := $(BUILD_DIR)/tests/NppMacCodeFormatterTests
MARKDOWN_TEST_BIN := $(BUILD_DIR)/tests/NppMacMarkdownRendererTests
MARKDOWN_PREVIEW_TEST_BIN := $(BUILD_DIR)/tests/NppMacMarkdownPreviewTests
FILE_DROP_TEST_BIN := $(BUILD_DIR)/tests/NppMacFileDropTests

CXX := clang++
CXXFLAGS := -std=c++17 -fobjc-arc -fobjc-weak -fmodules -mmacosx-version-min=10.13 $(ARCH_FLAGS) \
	-Isrc \
	-I$(SCINTILLA_FRAMEWORK)/Headers \
	-I$(ROOT_DIR)/scintilla/include \
	-I$(ROOT_DIR)/scintilla/cocoa \
	-I$(ROOT_DIR)/lexilla/include
LDFLAGS := -F$(SCINTILLA_PRODUCTS) -framework Cocoa -framework WebKit -framework Scintilla \
	-Wl,-rpath,@executable_path/../Frameworks

LEXILLA_CXXFLAGS := -std=c++17 -DNDEBUG -fPIC -fvisibility=hidden -O3 -Wpedantic -Wall -Wextra $(ARCH_FLAGS) \
	-I$(ROOT_DIR)/lexilla/include \
	-I$(ROOT_DIR)/scintilla/include \
	-I$(ROOT_DIR)/lexilla/lexlib
LEXILLA_LDFLAGS := -dynamiclib $(ARCH_FLAGS) -install_name @rpath/liblexilla.dylib

.PHONY: all scintilla lexilla app test run open clean

all: app

scintilla:
	xcodebuild -project $(SCINTILLA_PROJECT) \
		-scheme Scintilla \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(SCINTILLA_DERIVED) \
		ARCHS="$(ARCHS)" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGNING_ALLOWED=NO \
		build

$(LEXILLA_OBJ_DIR):
	mkdir -p $(LEXILLA_OBJ_DIR)

$(LEXILLA_OBJ_DIR)/%.o: $(LEXILLA_SRC_DIR)/%.cxx | $(LEXILLA_OBJ_DIR)
	$(CXX) $(LEXILLA_CXXFLAGS) -c $< -o $@

$(LEXILLA_OBJ_DIR)/%.o: $(LEXILLA_LEXLIB_DIR)/%.cxx | $(LEXILLA_OBJ_DIR)
	$(CXX) $(LEXILLA_CXXFLAGS) -c $< -o $@

$(LEXILLA_OBJ_DIR)/%.o: $(LEXILLA_LEXERS_DIR)/%.cxx | $(LEXILLA_OBJ_DIR)
	$(CXX) $(LEXILLA_CXXFLAGS) -c $< -o $@

$(LEXILLA_DYLIB): $(LEXILLA_OBJS)
	$(CXX) $(LEXILLA_LDFLAGS) $^ -o $@

lexilla: $(LEXILLA_DYLIB)

$(BIN): $(SRC) scintilla lexilla
	mkdir -p $(MACOS_DIR) $(FRAMEWORKS_DIR) $(RESOURCES_DIR)
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	sh scripts/generate-app-icon.sh $(ROOT_DIR)/PowerEditor/src/icons/npp.ico $(RESOURCES_DIR)/AppIcon.icns
	rm -rf $(RESOURCES_DIR)/en.lproj $(RESOURCES_DIR)/zh-Hans.lproj
	cp -R Resources/en.lproj Resources/zh-Hans.lproj $(RESOURCES_DIR)/
	cp $(ROOT_DIR)/PowerEditor/src/langs.model.xml $(RESOURCES_DIR)/langs.model.xml
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/saved.ico $(RESOURCES_DIR)/tab-saved.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/unsaved.ico $(RESOURCES_DIR)/tab-unsaved.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/closeTabButton.ico $(RESOURCES_DIR)/tab-close.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/closeTabButton_hoverIn.ico $(RESOURCES_DIR)/tab-close-hover.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/closeTabButton_hoverOnTab.ico $(RESOURCES_DIR)/tab-close-tab-hover.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/standard/tabbar/closeTabButton_push.ico $(RESOURCES_DIR)/tab-close-pressed.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/dark/tabbar/unsaved.ico $(RESOURCES_DIR)/tab-dark-unsaved.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/dark/tabbar/closeTabButton.ico $(RESOURCES_DIR)/tab-dark-close.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/dark/tabbar/closeTabButton_hoverIn.ico $(RESOURCES_DIR)/tab-dark-close-hover.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/dark/tabbar/closeTabButton_hoverOnTab.ico $(RESOURCES_DIR)/tab-dark-close-tab-hover.png
	sh scripts/extract-ico-png.sh $(ROOT_DIR)/PowerEditor/src/icons/dark/tabbar/closeTabButton_push.ico $(RESOURCES_DIR)/tab-dark-close-pressed.png
	rm -rf $(FRAMEWORKS_DIR)/Scintilla.framework
	cp -R $(SCINTILLA_FRAMEWORK) $(FRAMEWORKS_DIR)/
	cp $(LEXILLA_DYLIB) $(FRAMEWORKS_DIR)/
	$(CXX) $(CXXFLAGS) $(SRC) $(LDFLAGS) -o $(BIN)
	codesign --force --sign - $(FRAMEWORKS_DIR)/Scintilla.framework
	codesign --force --sign - $(FRAMEWORKS_DIR)/liblexilla.dylib
	codesign --force --deep --sign - $(APP_DIR)

app: $(BIN)
	@echo "Built $(APP_DIR)"

$(FIND_TEST_BIN): tests/NppMacFindPanelTests.mm src/NppMacFindPanelController.mm src/NppMacLocalization.mm scintilla
	mkdir -p $(dir $(FIND_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacFindPanelTests.mm src/NppMacFindPanelController.mm src/NppMacLocalization.mm \
		-F$(SCINTILLA_PRODUCTS) -framework Cocoa -framework Scintilla \
		-Wl,-rpath,$(abspath $(SCINTILLA_PRODUCTS)) -o $(FIND_TEST_BIN)

$(SESSION_TEST_BIN): tests/NppMacSessionStoreTests.mm src/NppMacSessionStore.mm
	mkdir -p $(dir $(SESSION_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacSessionStoreTests.mm src/NppMacSessionStore.mm \
		-framework Foundation -o $(SESSION_TEST_BIN)

$(SESSION_RESTORE_TEST_BIN): tests/NppMacSessionRestoreTests.mm src/NppMacAppDelegate.mm \
		src/NppMacCodeFormatter.mm src/NppMacFileDropView.mm src/NppMacFindPanelController.mm src/NppMacLanguageCatalog.mm src/NppMacMarkdownPreviewController.mm \
		src/NppMacMarkdownRenderer.mm src/NppMacPreferencesController.mm src/NppMacRecoveryStore.mm \
		src/NppMacLocalization.mm src/NppMacSessionStore.mm src/NppMacTabBarView.mm scintilla
	mkdir -p $(dir $(SESSION_RESTORE_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacSessionRestoreTests.mm src/NppMacAppDelegate.mm \
		src/NppMacCodeFormatter.mm src/NppMacFileDropView.mm src/NppMacFindPanelController.mm src/NppMacLanguageCatalog.mm src/NppMacMarkdownPreviewController.mm \
		src/NppMacMarkdownRenderer.mm src/NppMacPreferencesController.mm src/NppMacRecoveryStore.mm \
		src/NppMacLocalization.mm src/NppMacSessionStore.mm src/NppMacTabBarView.mm \
		-F$(SCINTILLA_PRODUCTS) -framework Cocoa -framework WebKit -framework Scintilla \
		-Wl,-rpath,$(abspath $(SCINTILLA_PRODUCTS)) -o $(SESSION_RESTORE_TEST_BIN)

$(PREFERENCES_TEST_BIN): tests/NppMacPreferencesTests.mm src/NppMacPreferencesController.mm src/NppMacLocalization.mm
	mkdir -p $(dir $(PREFERENCES_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacPreferencesTests.mm src/NppMacPreferencesController.mm src/NppMacLocalization.mm \
		-framework Cocoa -o $(PREFERENCES_TEST_BIN)

$(RECOVERY_TEST_BIN): tests/NppMacRecoveryStoreTests.mm src/NppMacRecoveryStore.mm
	mkdir -p $(dir $(RECOVERY_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacRecoveryStoreTests.mm src/NppMacRecoveryStore.mm \
		-framework Foundation -o $(RECOVERY_TEST_BIN)

$(LANGUAGE_TEST_BIN): tests/NppMacLanguageCatalogTests.mm src/NppMacLanguageCatalog.mm
	mkdir -p $(dir $(LANGUAGE_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacLanguageCatalogTests.mm src/NppMacLanguageCatalog.mm \
		-framework Foundation -o $(LANGUAGE_TEST_BIN)

$(LEXILLA_TEST_BIN): tests/NppMacLexillaTests.cxx lexilla
	mkdir -p $(dir $(LEXILLA_TEST_BIN))
	$(CXX) -std=c++17 -mmacosx-version-min=10.13 $(ARCH_FLAGS) \
		-I$(ROOT_DIR)/scintilla/include -I$(ROOT_DIR)/lexilla/include \
		tests/NppMacLexillaTests.cxx -o $(LEXILLA_TEST_BIN)

$(TAB_BAR_TEST_BIN): tests/NppMacTabBarTests.mm src/NppMacTabBarView.mm src/NppMacLocalization.mm
	mkdir -p $(dir $(TAB_BAR_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacTabBarTests.mm src/NppMacTabBarView.mm src/NppMacLocalization.mm \
		-framework Cocoa -o $(TAB_BAR_TEST_BIN)

$(LOCALIZATION_TEST_BIN): tests/NppMacLocalizationTests.mm src/NppMacLocalization.mm
	mkdir -p $(dir $(LOCALIZATION_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacLocalizationTests.mm src/NppMacLocalization.mm \
		-framework Foundation -o $(LOCALIZATION_TEST_BIN)

$(FORMATTER_TEST_BIN): tests/NppMacCodeFormatterTests.mm src/NppMacCodeFormatter.mm
	mkdir -p $(dir $(FORMATTER_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacCodeFormatterTests.mm src/NppMacCodeFormatter.mm \
		-framework Foundation -o $(FORMATTER_TEST_BIN)

$(MARKDOWN_TEST_BIN): tests/NppMacMarkdownRendererTests.mm src/NppMacMarkdownRenderer.mm
	mkdir -p $(dir $(MARKDOWN_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacMarkdownRendererTests.mm src/NppMacMarkdownRenderer.mm \
		-framework Foundation -o $(MARKDOWN_TEST_BIN)

$(MARKDOWN_PREVIEW_TEST_BIN): tests/NppMacMarkdownPreviewTests.mm src/NppMacMarkdownPreviewController.mm src/NppMacMarkdownRenderer.mm
	mkdir -p $(dir $(MARKDOWN_PREVIEW_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacMarkdownPreviewTests.mm src/NppMacMarkdownPreviewController.mm src/NppMacMarkdownRenderer.mm \
		-framework Cocoa -framework WebKit -o $(MARKDOWN_PREVIEW_TEST_BIN)

$(FILE_DROP_TEST_BIN): tests/NppMacFileDropTests.mm src/NppMacFileDropView.mm
	mkdir -p $(dir $(FILE_DROP_TEST_BIN))
	$(CXX) $(CXXFLAGS) tests/NppMacFileDropTests.mm src/NppMacFileDropView.mm \
		-framework Cocoa -o $(FILE_DROP_TEST_BIN)

test: $(FIND_TEST_BIN) $(SESSION_TEST_BIN) $(SESSION_RESTORE_TEST_BIN) $(PREFERENCES_TEST_BIN) \
		$(RECOVERY_TEST_BIN) $(LANGUAGE_TEST_BIN) $(LEXILLA_TEST_BIN) $(TAB_BAR_TEST_BIN) $(LOCALIZATION_TEST_BIN) \
		$(FORMATTER_TEST_BIN) $(MARKDOWN_TEST_BIN) $(MARKDOWN_PREVIEW_TEST_BIN) $(FILE_DROP_TEST_BIN)
	$(FIND_TEST_BIN)
	$(SESSION_TEST_BIN)
	$(SESSION_RESTORE_TEST_BIN)
	$(PREFERENCES_TEST_BIN)
	$(RECOVERY_TEST_BIN)
	$(LANGUAGE_TEST_BIN) $(ROOT_DIR)/PowerEditor/src/langs.model.xml
	$(LEXILLA_TEST_BIN) $(abspath $(LEXILLA_DYLIB))
	$(TAB_BAR_TEST_BIN)
	$(LOCALIZATION_TEST_BIN)
	$(FORMATTER_TEST_BIN)
	$(MARKDOWN_TEST_BIN)
	$(MARKDOWN_PREVIEW_TEST_BIN)
	$(FILE_DROP_TEST_BIN)

run: app
	open $(APP_DIR)

open: run

clean:
	rm -rf $(BUILD_DIR)
