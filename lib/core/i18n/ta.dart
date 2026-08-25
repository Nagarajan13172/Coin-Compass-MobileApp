/// The Tamil dictionary — **the switch that turns Tamil on**.
///
/// Phase 7.1. This map is the single source of truth for whether the app
/// offers Tamil at all: `SupportedLocales.hasTamil` is `taStrings.isNotEmpty`,
/// so the language toggle in the app bar appears the moment the first entry
/// lands here and disappears if they are all removed. Nobody has to remember
/// to un-hide anything.
///
/// Keys mirror `en.dart` exactly. A key that is missing or blank here falls
/// back to the English string for that key — see `Strings.t` — so a
/// half-translated dictionary renders as a mix of Tamil and English rather
/// than leaking raw keys like `dash.netWorth` at the owner.
///
/// **Tamil needs a font Inter does not have.** Inter carries no Tamil glyphs,
/// so text rendered from this map will come out as tofu (□□□) until Noto Sans
/// Tamil is bundled and the theme falls back to it. Populating this map is not
/// enough on its own.
const Map<String, String> taStrings = <String, String>{};
