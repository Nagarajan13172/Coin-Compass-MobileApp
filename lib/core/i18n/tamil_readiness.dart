/// Whether Tamil is complete enough to offer in the app bar.
///
/// ## Why this is a hand-written constant and not a computed one
///
/// Phase 7.1a derived availability from the dictionary itself — `hasTamil` was
/// `taStrings.isNotEmpty`, later "Tamil covers every English key" — so nobody
/// could forget to flip a switch in either direction. Moving to `gen-l10n`
/// takes that away: `L` is an abstract class of getters, and Dart cannot
/// enumerate them at runtime without reflection, so the app genuinely cannot
/// count its own coverage while it is running.
///
/// So the check moves from run time to test time, and keeps the same property.
/// `flutter gen-l10n` writes `lib/l10n/untranslated.json` on every build,
/// listing exactly which keys each locale is still missing.
/// `tamil_readiness_test.dart` reads that report and asserts this constant
/// agrees with it — **in both directions**:
///
///   * flip this to `true` while keys are missing and the test fails;
///   * finish every key and leave this `false`, and the test fails too, with
///     the message telling you to flip it.
///
/// The thing that must never happen is still unconstructable: a `த` label over
/// mostly-English text. It is now a red test instead of a hidden widget, which
/// is a fair trade for compile-time key safety across ~1,240 strings.
///
/// Phase 7.1b keeps *adding* English keys as it extracts hardcoded copy, and
/// every one of those re-opens a gap in the report — so the bar rises with the
/// work rather than being passed once and forgotten.
const bool kTamilReady = false;
