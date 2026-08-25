import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta'),
  ];

  /// migrated from app.name
  ///
  /// In en, this message translates to:
  /// **'CoinCompass'**
  String get appName;

  /// migrated from app.tagline
  ///
  /// In en, this message translates to:
  /// **'Personal Finance Manager'**
  String get appTagline;

  /// migrated from nav.dashboard
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// migrated from nav.transactions
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get navTransactions;

  /// migrated from nav.reports
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// migrated from nav.calendar
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// migrated from nav.budgets
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get navBudgets;

  /// migrated from nav.goals
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get navGoals;

  /// migrated from nav.accounts
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// migrated from nav.credits
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get navCredits;

  /// migrated from nav.recurring
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get navRecurring;

  /// migrated from nav.categories
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// migrated from nav.netWorth
  ///
  /// In en, this message translates to:
  /// **'Net Worth'**
  String get navNetWorth;

  /// migrated from nav.stocks
  ///
  /// In en, this message translates to:
  /// **'Stocks'**
  String get navStocks;

  /// migrated from nav.loans
  ///
  /// In en, this message translates to:
  /// **'Loans'**
  String get navLoans;

  /// migrated from nav.gold
  ///
  /// In en, this message translates to:
  /// **'Gold & Silver'**
  String get navGold;

  /// migrated from nav.insights
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get navInsights;

  /// migrated from nav.notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// migrated from nav.settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// migrated from nav.more
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// migrated from action.add
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// migrated from action.save
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// migrated from action.cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// migrated from action.delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// migrated from action.edit
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// migrated from action.retry
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// migrated from action.viewAll
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get actionViewAll;

  /// migrated from action.view
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get actionView;

  /// migrated from action.search
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// migrated from action.close
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// migrated from action.confirm
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// migrated from action.undo
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// migrated from action.done
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// migrated from action.refresh
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// migrated from action.breakdown
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get actionBreakdown;

  /// migrated from period.week
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get periodWeek;

  /// migrated from period.month
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get periodMonth;

  /// migrated from period.year
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get periodYear;

  /// migrated from period.thisMonth
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get periodThisMonth;

  /// migrated from period.thisWeek
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get periodThisWeek;

  /// migrated from period.thisYear
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get periodThisYear;

  /// migrated from money.income
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get moneyIncome;

  /// migrated from money.expense
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get moneyExpense;

  /// migrated from money.net
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get moneyNet;

  /// migrated from money.balance
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get moneyBalance;

  /// migrated from money.total
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get moneyTotal;

  /// migrated from money.netWorth
  ///
  /// In en, this message translates to:
  /// **'Net worth'**
  String get moneyNetWorth;

  /// migrated from money.transfer
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get moneyTransfer;

  /// migrated from dash.goodMorning
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String dashGoodMorning(Object name);

  /// migrated from dash.goodAfternoon
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String dashGoodAfternoon(Object name);

  /// migrated from dash.goodEvening
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String dashGoodEvening(Object name);

  /// migrated from dash.avgPerDay
  ///
  /// In en, this message translates to:
  /// **'Avg spend / day'**
  String get dashAvgPerDay;

  /// migrated from dash.biggestCategory
  ///
  /// In en, this message translates to:
  /// **'Biggest category'**
  String get dashBiggestCategory;

  /// migrated from dash.transactions
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get dashTransactions;

  /// migrated from dash.noIncome
  ///
  /// In en, this message translates to:
  /// **'No income this period'**
  String get dashNoIncome;

  /// migrated from dash.netWorthCaption
  ///
  /// In en, this message translates to:
  /// **'Everything you own, minus what you owe'**
  String get dashNetWorthCaption;

  /// migrated from dash.spendingByCategory
  ///
  /// In en, this message translates to:
  /// **'Spending by category'**
  String get dashSpendingByCategory;

  /// migrated from dash.recent
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get dashRecent;

  /// migrated from dash.netThisPeriod
  ///
  /// In en, this message translates to:
  /// **'Net this period'**
  String get dashNetThisPeriod;

  /// migrated from dash.totalEarned
  ///
  /// In en, this message translates to:
  /// **'Total earned'**
  String get dashTotalEarned;

  /// migrated from dash.totalSpent
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get dashTotalSpent;

  /// migrated from dash.groups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get dashGroups;

  /// migrated from dash.all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dashAll;

  /// migrated from dash.viewInReports
  ///
  /// In en, this message translates to:
  /// **'View in Reports'**
  String get dashViewInReports;

  /// migrated from auth.welcomeBack
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// migrated from auth.signInSubtitle
  ///
  /// In en, this message translates to:
  /// **'Sign in to your CoinCompass'**
  String get authSignInSubtitle;

  /// migrated from auth.email
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// migrated from auth.password
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// migrated from auth.confirmPassword
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPassword;

  /// migrated from auth.name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authName;

  /// migrated from auth.forgotPassword
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// migrated from auth.staySignedIn
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get authStaySignedIn;

  /// migrated from auth.signIn
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// migrated from auth.signUp
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// migrated from auth.signOut
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authSignOut;

  /// migrated from auth.orContinueWith
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get authOrContinueWith;

  /// migrated from auth.google
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get authGoogle;

  /// migrated from auth.haveAccount
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHaveAccount;

  /// migrated from auth.createAccount
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateAccount;

  /// migrated from auth.signUpSubtitle
  ///
  /// In en, this message translates to:
  /// **'Start tracking your money'**
  String get authSignUpSubtitle;

  /// migrated from auth.resetTitle
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetTitle;

  /// migrated from auth.sendResetLink
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get authSendResetLink;

  /// migrated from auth.resetSent
  ///
  /// In en, this message translates to:
  /// **'Check your inbox for the reset link.'**
  String get authResetSent;

  /// migrated from auth.backToSignIn
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get authBackToSignIn;

  /// migrated from auth.twoFactorTitle
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get authTwoFactorTitle;

  /// migrated from auth.twoFactorSubtitle
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app'**
  String get authTwoFactorSubtitle;

  /// migrated from auth.twoFactorCode
  ///
  /// In en, this message translates to:
  /// **'Authentication code'**
  String get authTwoFactorCode;

  /// migrated from auth.useBackupCode
  ///
  /// In en, this message translates to:
  /// **'Use a backup code instead'**
  String get authUseBackupCode;

  /// migrated from auth.useAuthCode
  ///
  /// In en, this message translates to:
  /// **'Use an authenticator code instead'**
  String get authUseAuthCode;

  /// migrated from auth.emailCode
  ///
  /// In en, this message translates to:
  /// **'Email me a code'**
  String get authEmailCode;

  /// migrated from auth.verify
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authVerify;

  /// migrated from auth.oauthComingSoon
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is coming soon on mobile.'**
  String get authOauthComingSoon;

  /// migrated from empty.noData
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyNoData;

  /// migrated from empty.noTransactions
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get emptyNoTransactions;

  /// migrated from empty.noAccounts
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get emptyNoAccounts;

  /// migrated from empty.comingNext
  ///
  /// In en, this message translates to:
  /// **'Coming next'**
  String get emptyComingNext;

  /// migrated from error.title
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// migrated from error.generic
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get errorGeneric;

  /// migrated from error.noConnection
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get errorNoConnection;

  /// migrated from misc.language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get miscLanguage;

  /// migrated from misc.tamilComingSoon
  ///
  /// In en, this message translates to:
  /// **'Tamil is coming soon.'**
  String get miscTamilComingSoon;

  /// migrated from misc.loading
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get miscLoading;

  /// migrated from misc.endOfDay
  ///
  /// In en, this message translates to:
  /// **'End of day'**
  String get miscEndOfDay;

  /// migrated from misc.allAccounts
  ///
  /// In en, this message translates to:
  /// **'All accounts'**
  String get miscAllAccounts;

  /// migrated from misc.quickAdd
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get miscQuickAdd;

  /// migrated from auth.noAccount
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccount;

  /// migrated from auth.resetSubtitle
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a reset link'**
  String get authResetSubtitle;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'ta':
      return LTa();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
