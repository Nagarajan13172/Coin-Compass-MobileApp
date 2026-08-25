/// Material, with the app's translating [Text] in place of Flutter's.
///
/// Phase 7.1. Importing this instead of `package:flutter/material.dart` is what
/// puts every string in a file through ML Kit — one line per file rather than
/// an edit at all 1,775 call sites.
///
/// Everything else is Material, re-exported unchanged, so the swap is invisible
/// apart from the translation itself.
library;

export 'package:flutter/material.dart' hide Text;

export 'i18n/translated_text.dart' show Text, TranslationScope, tr;
