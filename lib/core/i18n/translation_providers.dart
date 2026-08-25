import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_controller.dart';
import 'translator.dart';

/// The one [Translator] for the app's lifetime.
///
/// `ChangeNotifierProvider` rather than a plain `Provider`, so watching it
/// rebuilds on `notifyListeners`. The first version listened by hand and called
/// `ref.invalidateSelf()` from inside the callback — which re-ran the provider,
/// registered a second listener, and looped. Riverpod already does this
/// correctly; there was no reason to hand-roll it.
///
/// Kept alive deliberately: the cache inside it is the only thing between the
/// owner and re-translating the same forty labels every time they open
/// Settings.
final translatorProvider = ChangeNotifierProvider<Translator>(
  (ref) => Translator(),
);

/// Where the Tamil language pack is: absent, downloading, ready.
final translationModelStateProvider = Provider<ModelState>(
  (ref) => ref.watch(translatorProvider).modelState,
);

/// Turns the translator on and off in step with the chosen locale.
///
/// This is the whole join between "the owner picked Tamil" and "text comes out
/// in Tamil". It lives in a provider rather than in the toggle's `onTap` so
/// that a Tamil locale restored from SharedPreferences at launch switches
/// translation on too — otherwise the app would come back claiming Tamil and
/// rendering English, which is the exact bug 7.1a existed to fix.
final translationSyncProvider = Provider<void>((ref) {
  final translator = ref.watch(translatorProvider);
  final locale = ref.watch(localeControllerProvider);
  translator.setEnabled(
    locale.languageCode == SupportedLocales.tamil.languageCode,
  );
});

/// True once Tamil can actually be rendered — the pack is on the device.
///
/// Replaces phase 7.1a's ARB-coverage flag. The question is the one it always
/// was ("is Tamil real yet?"); only the thing that answers it changed, from
/// "is the dictionary complete" to "is the model downloaded".
final tamilAvailableProvider = Provider<bool>(
  (ref) => ref.watch(translationModelStateProvider) == ModelState.downloaded,
);
