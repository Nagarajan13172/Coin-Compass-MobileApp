// Enum vocabularies extracted from the backend's Zod schemas by probing every
// write endpoint with an invalid value. See docs/SPEC.md section 1.
//
// Every `fromApi` is tolerant: an unrecognised value maps to a safe default
// rather than throwing, so a server-side addition can never crash the app.

enum TransactionType {
  income('income'),
  expense('expense'),
  transfer('transfer');

  const TransactionType(this.api);
  final String api;

  static TransactionType fromApi(String? value) => switch (value) {
    'income' => TransactionType.income,
    'transfer' => TransactionType.transfer,
    _ => TransactionType.expense,
  };

  String get label => switch (this) {
    TransactionType.income => 'Income',
    TransactionType.expense => 'Expense',
    TransactionType.transfer => 'Transfer',
  };
}

enum AccountType {
  cash('cash'),
  bank('bank'),
  card('card'),
  wallet('wallet'),
  upi('upi'),
  savings('savings'),
  demat('demat');

  const AccountType(this.api);
  final String api;

  static AccountType fromApi(String? value) => AccountType.values.firstWhere(
    (e) => e.api == value,
    orElse: () => AccountType.bank,
  );

  String get label => switch (this) {
    AccountType.cash => 'Cash',
    AccountType.bank => 'Bank',
    AccountType.card => 'Card',
    AccountType.wallet => 'Wallet',
    AccountType.upi => 'UPI',
    AccountType.savings => 'Savings',
    AccountType.demat => 'Demat',
  };

  String get icon => switch (this) {
    AccountType.cash => 'banknote',
    AccountType.bank => 'landmark',
    AccountType.card => 'credit-card',
    AccountType.wallet => 'wallet',
    AccountType.upi => 'smartphone',
    AccountType.savings => 'piggy-bank',
    AccountType.demat => 'trending-up',
  };
}

enum CategoryType {
  income('income'),
  expense('expense');

  const CategoryType(this.api);
  final String api;

  static CategoryType fromApi(String? value) =>
      value == 'income' ? CategoryType.income : CategoryType.expense;

  String get label => this == CategoryType.income ? 'Income' : 'Expense';
}

enum BudgetPeriod {
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const BudgetPeriod(this.api);
  final String api;

  static BudgetPeriod fromApi(String? value) => BudgetPeriod.values.firstWhere(
    (e) => e.api == value,
    orElse: () => BudgetPeriod.monthly,
  );

  String get label => switch (this) {
    BudgetPeriod.weekly => 'Weekly',
    BudgetPeriod.monthly => 'Monthly',
    BudgetPeriod.yearly => 'Yearly',
  };
}

enum LoanType {
  home('home'),
  personal('personal'),
  car('car'),
  education('education'),
  gold('gold'),
  business('business'),
  other('other');

  const LoanType(this.api);
  final String api;

  static LoanType fromApi(String? value) => LoanType.values.firstWhere(
    (e) => e.api == value,
    orElse: () => LoanType.other,
  );

  String get label => switch (this) {
    LoanType.home => 'Home',
    LoanType.personal => 'Personal',
    LoanType.car => 'Car',
    LoanType.education => 'Education',
    LoanType.gold => 'Gold',
    LoanType.business => 'Business',
    LoanType.other => 'Other',
  };

  String get icon => switch (this) {
    LoanType.home => 'home',
    LoanType.personal => 'banknote',
    LoanType.car => 'car',
    LoanType.education => 'graduation-cap',
    LoanType.gold => 'coins',
    LoanType.business => 'briefcase',
    LoanType.other => 'ellipsis',
  };
}

enum LoanStatus {
  active('active'),
  closed('closed');

  const LoanStatus(this.api);
  final String api;

  static LoanStatus fromApi(String? value) =>
      value == 'closed' ? LoanStatus.closed : LoanStatus.active;

  String get label => this == LoanStatus.active ? 'Active' : 'Closed';
}

enum CreditDirection {
  given('given'),
  received('received'),
  borrowed('borrowed'),
  repaid('repaid');

  const CreditDirection(this.api);
  final String api;

  static CreditDirection fromApi(String? value) => CreditDirection.values
      .firstWhere((e) => e.api == value, orElse: () => CreditDirection.given);

  String get label => switch (this) {
    CreditDirection.given => 'Given',
    CreditDirection.received => 'Received',
    CreditDirection.borrowed => 'Borrowed',
    CreditDirection.repaid => 'Repaid',
  };

  /// `given` and `borrowed` mean money is owed to / by you respectively.
  bool get isOutgoing =>
      this == CreditDirection.given || this == CreditDirection.repaid;
}

enum Frequency {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const Frequency(this.api);
  final String api;

  static Frequency fromApi(String? value) => Frequency.values.firstWhere(
    (e) => e.api == value,
    orElse: () => Frequency.monthly,
  );

  String get label => switch (this) {
    Frequency.daily => 'Daily',
    Frequency.weekly => 'Weekly',
    Frequency.monthly => 'Monthly',
    Frequency.yearly => 'Yearly',
  };
}

enum HoldingClass {
  saving('saving'),
  investment('investment');

  const HoldingClass(this.api);
  final String api;

  static HoldingClass fromApi(String? value) =>
      value == 'investment' ? HoldingClass.investment : HoldingClass.saving;

  String get label => this == HoldingClass.saving ? 'Saving' : 'Investment';
}

/// A subtype belongs to exactly one class. The API accepts `class` and
/// `subtype` as two independent keys and validates each against its own enum,
/// so `{class: 'saving', subtype: 'stocks'}` is written without complaint — and
/// the holding then lands on the wrong side of the saving/investment split. The
/// pairing is the web app's, and it lives here so a form cannot get it wrong.
enum HoldingSubtype {
  fixedDeposit('fixed_deposit', 'Fixed Deposit', HoldingClass.saving),
  recurringDeposit('recurring_deposit', 'Recurring Deposit',
      HoldingClass.saving),
  emergencyFund('emergency_fund', 'Emergency Fund', HoldingClass.saving),
  retirementFund('retirement_fund', 'Retirement Fund', HoldingClass.saving),
  stocks('stocks', 'Stocks', HoldingClass.investment),
  mutualFunds('mutual_funds', 'Mutual Funds', HoldingClass.investment),
  realEstate('real_estate', 'Real Estate', HoldingClass.investment),
  bonds('bonds', 'Bonds', HoldingClass.investment),
  gold('gold', 'Gold', HoldingClass.investment);

  const HoldingSubtype(this.api, this.label, this.holdingClass);
  final String api;
  final String label;

  /// The class this subtype must be filed under.
  final HoldingClass holdingClass;

  /// The subtypes a given class may hold — the Type select's whole option list.
  static List<HoldingSubtype> forClass(HoldingClass c) =>
      values.where((s) => s.holdingClass == c).toList();

  static HoldingSubtype fromApi(String? value) =>
      HoldingSubtype.values.firstWhere(
        (e) => e.api == value,
        orElse: () => HoldingSubtype.fixedDeposit,
      );
}
