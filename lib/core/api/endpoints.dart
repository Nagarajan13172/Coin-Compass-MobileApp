/// Every backend path, relative to `ApiClient.baseUrl`
/// (`https://coincompass.sathishkumar.cloud/api`).
///
/// Verified live against the deployment — see docs/SPEC.md section 1.
class Endpoints {
  const Endpoints._();

  // ── auth ─────────────────────────────────────────────────────────────────
  static const String signin = '/auth/signin';
  static const String signup = '/auth/signup';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';
  static const String authProviders = '/auth/providers';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verifyEmail = '/auth/verify-email';
  static const String resendVerification = '/auth/resend-verification';
  static const String changePassword = '/auth/change-password';
  static const String lockWealth = '/auth/lock-wealth';
  static const String unlockWealth = '/auth/unlock-wealth';

  // ── two-factor ───────────────────────────────────────────────────────────
  static const String twoFactorStatus = '/auth/2fa/status';
  static const String twoFactorSetup = '/auth/2fa/setup';
  static const String twoFactorEnable = '/auth/2fa/enable';
  static const String twoFactorDisable = '/auth/2fa/disable';
  static const String twoFactorVerify = '/auth/2fa/verify';
  static const String twoFactorPending = '/auth/2fa/pending';
  static const String twoFactorEmail = '/auth/2fa/email';
  static const String twoFactorEmailFallback = '/auth/2fa/email-fallback';
  static const String twoFactorBackupCodes = '/auth/2fa/backup-codes';

  // ── transactions ─────────────────────────────────────────────────────────
  static const String transactions = '/transactions';
  static const String transactionsBalance = '/transactions/balance';
  static const String transactionsSummary = '/transactions/summary';
  static const String transactionsTags = '/transactions/tags';
  static const String transactionsDeleted = '/transactions/deleted';
  static String transaction(String id) => '/transactions/$id';
  static String transactionRestore(String id) => '/transactions/$id/restore';

  // ── accounts ─────────────────────────────────────────────────────────────
  static const String accounts = '/accounts';
  static String account(String id) => '/accounts/$id';

  // ── categories ───────────────────────────────────────────────────────────
  static const String categories = '/categories';
  static String category(String id) => '/categories/$id';

  // ── budgets ──────────────────────────────────────────────────────────────
  static const String budgets = '/budgets';
  static String budget(String id) => '/budgets/$id';

  // ── goals ────────────────────────────────────────────────────────────────
  static const String goals = '/goals';
  static String goal(String id) => '/goals/$id';
  static String goalContribute(String id) => '/goals/$id/contribute';

  // ── loans ────────────────────────────────────────────────────────────────
  static const String loans = '/loans';
  static String loan(String id) => '/loans/$id';
  static String loanPay(String id) => '/loans/$id/pay';
  static String loanPreclose(String id) => '/loans/$id/preclose';

  // ── credits ──────────────────────────────────────────────────────────────
  static const String credits = '/credits';
  static const String creditsSummary = '/credits/summary';
  static String credit(String id) => '/credits/$id';

  // ── people & groups ──────────────────────────────────────────────────────
  static const String people = '/people';
  static const String peopleGroups = '/people/groups';
  static String person(String id) => '/people/$id';
  static String personMerge(String id) => '/people/$id/merge';
  static String personGroup(String id) => '/people/groups/$id';

  // ── splits ───────────────────────────────────────────────────────────────
  static const String splits = '/splits';
  static String split(String id) => '/splits/$id';

  // ── recurring ────────────────────────────────────────────────────────────
  static const String recurring = '/recurring';
  static String recurringRule(String id) => '/recurring/$id';
  static String recurringRun(String id) => '/recurring/$id/run';
  static String recurringSkip(String id) => '/recurring/$id/skip';
  static String recurringPostOne(String id) => '/recurring/$id/post-one';
  static String recurringTransactions(String id) =>
      '/recurring/$id/transactions';

  // ── templates (quick add) ────────────────────────────────────────────────
  static const String templates = '/templates';
  static String template(String id) => '/templates/$id';

  // ── holdings ─────────────────────────────────────────────────────────────
  static const String holdings = '/holdings';
  static String holding(String id) => '/holdings/$id';

  // ── stocks ───────────────────────────────────────────────────────────────
  // NOTE: `GET /stocks` is a 404 — the portfolio lives at /stocks/portfolio.
  static const String stocksPortfolio = '/stocks/portfolio';
  static const String stocksSearch = '/stocks/search';
  static const String stocksBuy = '/stocks/buy';
  static const String stocksSell = '/stocks/sell';
  static const String stocksSales = '/stocks/sales';
  static const String stocksRefresh = '/stocks/refresh';
  static const String stocksSplits = '/stocks/splits';
  static const String stocksSplitsApply = '/stocks/splits/apply';
  static String stocksSale(String id) => '/stocks/sales/$id';
  static String stocksLot(String id) => '/stocks/lots/$id';

  // ── metals ───────────────────────────────────────────────────────────────
  static const String metalsLatest = '/metals/latest';
  static const String metalsRefresh = '/metals/refresh';
  static const String metalsHistory = '/metals/history';

  // ── net worth ────────────────────────────────────────────────────────────
  static const String netWorthHistory = '/networth/history';

  // ── reports ──────────────────────────────────────────────────────────────
  static const String reports = '/reports';
  static const String reportsSummary = '/reports/summary';
  static const String reportsByCategory = '/reports/by-category';
  static const String reportsByAccount = '/reports/by-account';
  static const String reportsTrend = '/reports/trend';
  static const String reportsInsights = '/reports/insights';
  static const String reportsEmailNow = '/reports/email-now';

  // ── notifications ────────────────────────────────────────────────────────
  static const String notifications = '/notifications';
  static const String notificationsReadAll = '/notifications/read-all';
  static String notification(String id) => '/notifications/$id';
  static String notificationRead(String id) => '/notifications/$id/read';

  // ── settings ─────────────────────────────────────────────────────────────
  static const String settings = '/settings';
  static const String settingsPin = '/settings/pin';
  static const String settingsPinVerify = '/settings/pin/verify';
  static const String settingsWealthPasscode = '/settings/wealth-passcode';

  // ── export ───────────────────────────────────────────────────────────────
  static const String exportCsv = '/export/csv';
}
