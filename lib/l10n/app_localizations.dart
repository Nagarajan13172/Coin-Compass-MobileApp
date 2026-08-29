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

  /// Bottom-nav slot that scans a UPI QR and pays it
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

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

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The PIN must be 4 to 8 digits.'**
  String get settingsSecPinMustDigits;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The two PINs don\'t match.'**
  String get settingsSecTwoPinsDontMatch;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Change your PIN'**
  String get settingsSecChangePin;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get settingsSecSetPin;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get settingsSecChangePinAction;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Turn on PIN lock'**
  String get settingsSecTurnPinLock;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Your data stays exactly as it is, and this is not your password.'**
  String get settingsSecDataStaysExactlyAs;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Choose 4 to 8 digits. This PIN protects CoinCompass in a browser. To lock this phone, use App lock at the top of the Security card.'**
  String get settingsSecChooseDigitsPinProtects;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get settingsSecNewPin;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get settingsSecConfirmPin;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The passcode must be 4 to 32 characters.'**
  String get settingsSecPasscodeMustCharacters;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The two passcodes don\'t match.'**
  String get settingsSecTwoPasscodesDontMatch;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Change the passcode'**
  String get settingsSecChangePasscode;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Set a passcode'**
  String get settingsSecSetPasscode;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Change passcode'**
  String get settingsSecChangePasscodeAction;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Lock Net Worth'**
  String get settingsSecLockNetWorth;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth, Savings & Investments and Stocks stay hidden until this passcode is entered. Each place you sign in asks for it separately. Keep it somewhere safe — this app cannot clear a passcode you have forgotten; you would have to remove it from CoinCompass in a browser.'**
  String get settingsSecNetWorthSavingsInvestments;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Between 4 and 32 characters. Letters, digits and symbols all count. It hides the totals: your accounts, balances, loans and transactions stay visible, and so do income, expenses and cash flow.'**
  String get settingsSecBetweenCharactersLettersDigits;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Wealth passcode'**
  String get settingsSecWealthPasscode;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get settingsSecHide;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get settingsSecShow;

  /// security_sheets.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Confirm passcode'**
  String get settingsSecConfirmPasscode;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get settingsProfileSigned;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Sign in again to see your account details.'**
  String get settingsProfileSignAgainSeeAccount;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get settingsProfileAccount;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get settingsProfileVerified;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get settingsProfileUnverified;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Wealth view'**
  String get settingsProfileWealthView;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Email & password'**
  String get settingsProfileEmailPassword;

  /// profile_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Google account'**
  String get settingsProfileGoogleAccount;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Preferences & data'**
  String get settingsPreferencesData;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Applies instantly, and is saved to your account.'**
  String get settingsAppliesInstantlySavedAccount;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsLight;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsDark;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The web app keeps the theme on the device it was picked on. This app also stores it on your account so a reinstall remembers it.'**
  String get settingsWebAppKeepsTheme;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Wallet updated'**
  String get settingsWalletUpdated;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get settingsWallet;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'What this wallet is called inside the app.'**
  String get settingsWhatWalletCalledInside;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Wallet name'**
  String get settingsWalletName;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'My Wallet'**
  String get settingsMyWallet;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get settingsLabel;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'e.g. Personal finances'**
  String get settingsEGPersonalFinances;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'An optional tag shown alongside your wallet name.'**
  String get settingsOptionalTagShownAlongside;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get settingsSaveChanges;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Base currency updated'**
  String get settingsBaseCurrencyUpdated;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Every amount in the app is shown in this currency.'**
  String get settingsEveryAmountAppShown;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'No currencies'**
  String get settingsNoCurrencies;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The server hasn\'t sent a currency table for this wallet, so amounts stay in the current base currency.'**
  String get settingsServerHasntSentCurrency;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Rates are seeded on the server and cannot be edited here — the web app has no editor for them either, and multi-currency conversion isn\'t enabled yet.'**
  String get settingsRatesSeededServerCannot;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Base currency'**
  String get settingsBaseCurrency;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Email reports'**
  String get settingsEmailReports;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Monthly & mid-month summary'**
  String get settingsMonthlyMidMonthSummary;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Emailed on the 1st (last month) and the 15th (this month so far).'**
  String get settingsEmailedStLastMonth;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Signing out…'**
  String get settingsSigningOut;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Signs you out on this device only. Your data stays on the server.'**
  String get settingsSignsOutDeviceOnly;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOut;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'You\'ll need your email and password to get back in.'**
  String get settingsYoullNeedEmailPassword;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'App info'**
  String get settingsAppInfo;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsApp;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get settingsBuild;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Local build · Single user'**
  String get settingsLocalBuildSingleUser;

  /// settings_screen.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get settingsRegion;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecuritySecurity;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'App lock (this phone)'**
  String get settingsSecurityAppLockPhone;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'CoinCompass asks for your fingerprint — or your PIN — when you open it, and again after 30 seconds away. Checked on this phone, so it works with no signal.'**
  String get settingsSecurityCoincompassAsksFingerprintPin;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'CoinCompass asks for your PIN when you open it, and again after 30 seconds away. It is checked on this phone, so it works with no signal.'**
  String get settingsSecurityCoincompassAsksPinWhen;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Ask for a PIN before CoinCompass opens on this phone. Checked on the device, so it works offline.'**
  String get settingsSecurityAskPinBeforeCoincompass;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get settingsSecurityLockNow;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get settingsSecurityTurnOff;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Set up app lock'**
  String get settingsSecuritySetUpAppLock;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint'**
  String get settingsSecurityUnlockFingerprint;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'PIN lock (web)'**
  String get settingsSecurityPinLockWeb;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'A 4–8 digit PIN is asked for when you open CoinCompass in a browser. The lock on this phone is the row above.'**
  String get settingsSecurityDigitPinAskedWhen;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Ask for a short PIN when you open CoinCompass in a browser.'**
  String get settingsSecurityAskShortPinWhen;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The app lock covers this phone and is checked on the device, so it works with no signal. The PIN lock covers CoinCompass in a browser. The Net Worth passcode is saved on your account, but each place you sign in asks for it separately. None of them is your account password, and none of them changes your data.'**
  String get settingsSecurityAppLockCoversPhone;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Turn off the app lock?'**
  String get settingsSecurityTurnOffAppLock;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'App lock turned off. Screenshots and the app-switcher preview work normally again.'**
  String get settingsSecurityAppLockTurnedOff;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Turn off the web PIN?'**
  String get settingsSecurityTurnOffWebPin;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'CoinCompass will stop asking for a PIN when you open it in a browser. The app lock on this phone is separate and stays as it is. You can set a new web PIN at any time.'**
  String get settingsSecurityCoincompassStopAskingPin;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'PIN lock turned off'**
  String get settingsSecurityPinLockTurnedOff;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth, Savings & Investments and Stocks are hidden until you enter the passcode. Unlocking here unlocks them in this app only — each place you sign in unlocks separately.'**
  String get settingsSecurityWealthLockedDescription;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth, Savings & Investments and Stocks are showing in this app. Locking hides them here again; anywhere else you are signed in keeps its own state.'**
  String get settingsSecurityWealthShowingDescription;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Hide Net Worth, Savings & Investments and Stocks behind a passcode. The passcode is saved on your account, and each place you sign in asks for it separately.'**
  String get settingsSecurityHideNetWorthSavings;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get settingsSecurityLocked;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get settingsSecurityUnlocked;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsSecurityOff;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth lock'**
  String get settingsSecurityNetWorthLock;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get settingsSecurityUnlock;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unlocked for this sign-in. Net Worth stays visible here until you lock it again or sign out.'**
  String get settingsSecurityUnlockedSignNetWorth;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Lock Net Worth again?'**
  String get settingsSecurityLockNetWorthAgain;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth, Savings & Investments and Stocks will be hidden until the passcode is entered again in this app. Your data is not changed.'**
  String get settingsSecurityWealthRelockWarning;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get settingsSecurityLock;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth locked in this app.'**
  String get settingsSecurityNetWorthLockedApp;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Turn off the Net Worth lock?'**
  String get settingsSecurityTurnOffNetWorth;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth, Savings & Investments and Stocks will be visible without a passcode, in every place you sign in. The passcode is discarded and cannot be recovered.'**
  String get settingsSecurityWealthTurnOffWarning;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Net Worth lock turned off.'**
  String get settingsSecurityNetWorthLockTurned;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Not set up. Turn it on from the web app — enrolling needs a QR scan.'**
  String get settingsSecuritySetUpTurnFrom;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settingsSecurityUnknown;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check the status just now.'**
  String get settingsSecurityCouldntCheckStatusJust;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsSecurityChecking;

  /// security_card.dart (7.1b)
  ///
  /// In en, this message translates to:
  /// **'The app lock turned itself off: the saved PIN check was missing. Set it up again.'**
  String get settingsSecurityAppLockTurnedItself;

  /// profile_card.dart (7.1b) — sign-in method and the month the account was created
  ///
  /// In en, this message translates to:
  /// **'{method} · Member since {month}'**
  String settingsProfileMemberSince(String method, String month);

  /// settings_screen.dart (7.1b) — the server refused the theme write
  ///
  /// In en, this message translates to:
  /// **'Theme applied here, but not saved: {failure}'**
  String settingsThemeNotSaved(String failure);

  /// settings_screen.dart (7.1b) — one unit of a currency in the base currency
  ///
  /// In en, this message translates to:
  /// **'1 {code} = {amount}'**
  String settingsCurrencyRate(String code, String amount);

  /// settings_screen.dart (7.1b) — a currency row: INR — Indian Rupee
  ///
  /// In en, this message translates to:
  /// **'{code} — {name}'**
  String settingsCurrencyCodeAndName(String code, String name);

  /// settings_screen.dart (7.1b) — App info region line
  ///
  /// In en, this message translates to:
  /// **'{currency} · {locale}'**
  String settingsRegionSummary(String currency, String locale);

  /// security_card.dart (7.1b) — 2FA status. `fallback` is empty or the email-fallback sentence.
  ///
  /// In en, this message translates to:
  /// **'Authenticator app is on. {fallback}{count, plural, =1{1 backup code left.} other{{count} backup codes left.}}'**
  String settingsSecurityTwoFactorOn(String fallback, int count);

  /// security_card.dart (7.1b) — prepended to the 2FA status when the emailed-code fallback is on
  ///
  /// In en, this message translates to:
  /// **'Email fallback is on. '**
  String get settingsSecurityEmailFallbackOn;

  /// security_card.dart (7.1b) — status pill, the pair of settingsSecurityOff
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsSecurityOn;
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
