import 'package:coincompass/core/i18n/translation_providers.dart';
import 'package:coincompass/core/i18n/translator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **What has to happen before the first frame.**
///
/// Found on the owner's phone: with Tamil downloaded and `locale: ta` in
/// SharedPreferences, the app relaunched in ENGLISH with no language pill. The
/// device was only asked where the language pack was when the Settings Language
/// card mounted, so a cold start never knew it existed — `ready` stayed false,
/// translation never switched on, and visiting Settings fixed it until the next
/// launch.
void main() {
  test('creating the translator asks the device for the model state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final translator = container.read(translatorProvider);
    expect(
      translator.modelState,
      ModelState.unknown,
      reason: 'the answer cannot be known synchronously',
    );

    // The startup refresh is fire-and-forget; let it land.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      translator.modelState,
      isNot(ModelState.unknown),
      reason:
          'a cold start must resolve the model state on its own, without '
          'waiting for someone to open Settings',
    );
  });

  test('tamilAvailableProvider is false until a model is actually there', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // No ML Kit in a test host, so this must never claim Tamil is usable.
    expect(container.read(tamilAvailableProvider), isFalse);
  });
}
