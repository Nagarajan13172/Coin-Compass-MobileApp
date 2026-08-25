/// What machine translation is allowed to touch, and what it must never touch.
///
/// ## Why this file exists
///
/// Runtime translation means no human reads the Tamil before the owner does.
/// That is fine for "Save" and fatal for "Outstanding", which on a loan card
/// means *balance remaining* and which general-purpose translators routinely
/// render as *சிறந்த* — "excellent". On a screen showing a ₹2,00,00,000 loan,
/// that is a caption that misdescribes money, which is the one failure this
/// project has spent its whole life eliminating.
///
/// So two guards sit in front of the translator:
///
///   1. [isTranslatable] — refuses anything that is a **figure** rather than
///      prose. A number must never go near a translator.
///   2. [glossary] — a hand-checked Tamil term for every finance word whose
///      machine translation would be wrong or ambiguous. Applied *instead of*
///      the model, not after it.
///
/// Everything else goes to ML Kit.
library;

/// Text that must be rendered exactly as given.
///
/// Deliberately broad. A false positive costs one untranslated English word; a
/// false negative can put a mangled number in front of the owner.
bool isTranslatable(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;

  // Nothing to translate without letters — figures, separators, punctuation.
  if (!_hasLetter.hasMatch(trimmed)) return false;

  // Any currency symbol at all: ₹2,00,00,000, $12, −₹13,312.
  if (_currency.hasMatch(trimmed)) return false;

  // Indian-grouped or decimal figures, percentages, compact suffixes
  // (₹1.37L, ~₹2.86Cr, 7.25%). These carry meaning in their exact shape.
  if (_figure.hasMatch(trimmed)) return false;

  // Dates and times as rendered — "04 Aug 2026", "5:30 AM".
  if (_dateOrTime.hasMatch(trimmed)) return false;

  // A lone identifier or code: INR, GBP, a ticker, an icon name.
  if (_codeLike.hasMatch(trimmed)) return false;

  // The product's own name is a proper noun in every language.
  if (trimmed == 'CoinCompass') return false;

  return true;
}

/// Finance terms whose machine translation would be wrong, ambiguous, or
/// inconsistent between screens.
///
/// Matched on the **whole string**, case-sensitively, before the model is
/// consulted — so "Outstanding" as a card label is fixed, while a sentence that
/// merely contains the word still goes to ML Kit. Sentence-level terminology is
/// the known weakness of this approach and is called out in the phase report.
///
/// Every entry here is a judgement about Tamil financial usage that a reviewer
/// should confirm; they are marked in `docs/PHASE7_TRANSLATION.md` for exactly
/// that.
const Map<String, String> glossary = <String, String>{
  // ── the ones that would actively mislead ────────────────────────────────
  // "Outstanding" as praise vs as a balance owed.
  'Outstanding': 'நிலுவைத் தொகை',
  // "Net" as in netting off, not a fishing net (வலை).
  'Net': 'நிகர',
  'Net worth': 'நிகர மதிப்பு',
  'Net / month': 'மாதத்திற்கு நிகரம்',
  // "Credit" as money lent, not praise or a film credit.
  'Credit': 'கடன் தொகை',
  'Credits': 'கடன் தொகைகள்',
  // "Principal" as loan capital, not a head teacher.
  'Principal': 'அசல் தொகை',
  // "Interest" as the money kind, not curiosity.
  'Interest': 'வட்டி',
  'Interest paid': 'செலுத்திய வட்டி',
  // "Balance" as money held, not equilibrium.
  'Balance': 'இருப்பு',
  'Total balance': 'மொத்த இருப்பு',
  // "Returns" as investment gain, not going back.
  'Returns': 'வருவாய்',

  // ── terms with no everyday Tamil equivalent ─────────────────────────────
  'Preclose': 'முன்கூட்டியே முடித்தல்',
  'EMI': 'மாதத் தவணை',
  'Part payment': 'பகுதிக் கட்டணம்',
  'Tenure left': 'மீதமுள்ள காலம்',
  'Demat': 'டீமேட்',

  // ── the money words the whole app is built on ───────────────────────────
  'Income': 'வருமானம்',
  'Expense': 'செலவு',
  'Expenses': 'செலவுகள்',
  'Assets': 'சொத்துக்கள்',
  'Liabilities': 'கடன்கள்',
  'Savings': 'சேமிப்பு',
  'Investments': 'முதலீடுகள்',
  'Holdings': 'சொத்து வைப்புகள்',
  'Loans': 'கடன்கள்',
  'Loan': 'கடன்',
  'Budget': 'நிதித் திட்டம்',
  'Budgets': 'நிதித் திட்டங்கள்',
  'Goals': 'இலக்குகள்',
  'Goal': 'இலக்கு',
  'Accounts': 'கணக்குகள்',
  'Account': 'கணக்கு',
  'Transactions': 'பரிவர்த்தனைகள்',
  'Transaction': 'பரிவர்த்தனை',
  'Transfer': 'பரிமாற்றம்',
  'Categories': 'வகைகள்',
  'Category': 'வகை',
  'Recurring': 'தொடர் பரிவர்த்தனைகள்',
  'Reports': 'அறிக்கைகள்',
  'Insights': 'நுண்ணறிவுகள்',
  'Dashboard': 'முகப்பு',
  'Calendar': 'நாட்காட்டி',
  'Settings': 'அமைப்புகள்',
  'Notifications': 'அறிவிப்புகள்',
  'Stocks': 'பங்குகள்',
  'Gold & Silver': 'தங்கம் & வெள்ளி',
  'People': 'நபர்கள்',
  'Splits': 'பகிர்வுகள்',
};

final RegExp _hasLetter = RegExp(r'[A-Za-z]');

/// Any currency symbol, anywhere in the string.
final RegExp _currency = RegExp(r'[₹$€£¥]');

/// A figure: grouped digits, a decimal, a percentage, or a compact suffix.
final RegExp _figure = RegExp(
  r'\d[\d,.]*\s*(?:%|L\b|Cr\b|K\b)|\d{1,3}(?:,\d{2,3})+|\b\d+\.\d+\b',
);

/// A rendered date or clock time.
final RegExp _dateOrTime = RegExp(
  r'\b\d{1,2}:\d{2}\b'
  r'|\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
  r'|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b',
);

/// An identifier rather than prose: `INR`, `credit-card`, `mt_session`.
final RegExp _codeLike = RegExp(r'^[A-Z]{2,5}$|^[a-z0-9]+(?:[-_][a-z0-9]+)+$');
