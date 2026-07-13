# macOS Porting Status

## Completed native core

| Area | macOS implementation |
| --- | --- |
| Toolbar | Original icon resources and command grouping with localized tooltips and live command state |
| Editor | Cocoa `ScintillaView`, UTF-8 internal document model, native undo/redo and clipboard |
| Documents | Original-style multi-buffer tabs with state icons, close controls, drag reordering and overflow scrolling; open/save/save as/reload, dirty state, close confirmation |
| Search | Four-tab find/replace/files/mark panel; normal, extended and regex modes; current/open-document and directory operations |
| Localization | Resource-key based runtime i18n; Simplified Chinese default and English selectable in Preferences |
| Recovery | Session restore plus delayed snapshots for unsaved and modified buffers |
| Search | Non-modal forward/backward find, replace current/all, case and whole-word options |
| Languages | Bundled Lexilla and Notepad++ `langs.model.xml` extension mapping |
| UDL engine | Real `LexUser.cxx` lexer compiled for macOS |
| Preferences | Font, size, indentation, line numbers, and wrapping persisted in `NSUserDefaults` |
| File safety | Original encoding preservation and external modification/deletion detection |
| Navigation | Tab cycling, go to line, live line/column and document status |
| Packaging | Universal 2 `.app`, embedded Universal 2 Scintilla/Lexilla, ad-hoc local signature |

## Not binary portable

The following Windows components cannot be loaded or reproduced through a
source-level macOS compile:

- existing Notepad++ plugin DLLs and their Win32 message/`HWND` ABI
- Explorer context-menu shell extensions
- Windows notification-area integration
- registry-backed settings and Windows file-association code
- Win32 docking-window implementations

Native macOS replacements would be new platform features with different APIs.
They are intentionally outside the native editor-core compatibility claim.

## Remaining optional extension

The UDL lexer is functional in the bundled Lexilla library. A Cocoa editor and
import workflow for user-defined-language XML files can be added independently;
it is not required by the 1.0 native editor core.
