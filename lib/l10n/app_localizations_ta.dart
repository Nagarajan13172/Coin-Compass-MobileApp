// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class LTa extends L {
  LTa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'CoinCompass';

  @override
  String get appTagline => 'Personal Finance Manager';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navReports => 'Reports';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navBudgets => 'Budgets';

  @override
  String get navGoals => 'Goals';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navCredits => 'Credits';

  @override
  String get navRecurring => 'Recurring';

  @override
  String get navCategories => 'Categories';

  @override
  String get navNetWorth => 'Net Worth';

  @override
  String get navStocks => 'Stocks';

  @override
  String get navLoans => 'Loans';

  @override
  String get navGold => 'Gold & Silver';

  @override
  String get navInsights => 'Insights';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMore => 'More';

  @override
  String get navScan => 'Scan';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionViewAll => 'View all';

  @override
  String get actionView => 'View';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionClose => 'Close';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionDone => 'Done';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionBreakdown => 'Breakdown';

  @override
  String get periodWeek => 'Week';

  @override
  String get periodMonth => 'Month';

  @override
  String get periodYear => 'Year';

  @override
  String get periodThisMonth => 'This month';

  @override
  String get periodThisWeek => 'This week';

  @override
  String get periodThisYear => 'This year';

  @override
  String get moneyIncome => 'Income';

  @override
  String get moneyExpense => 'Expense';

  @override
  String get moneyNet => 'Net';

  @override
  String get moneyBalance => 'Balance';

  @override
  String get moneyTotal => 'Total';

  @override
  String get moneyNetWorth => 'Net worth';

  @override
  String get moneyTransfer => 'Transfer';

  @override
  String dashGoodMorning(Object name) {
    return 'Good morning, $name';
  }

  @override
  String dashGoodAfternoon(Object name) {
    return 'Good afternoon, $name';
  }

  @override
  String dashGoodEvening(Object name) {
    return 'Good evening, $name';
  }

  @override
  String get dashAvgPerDay => 'Avg spend / day';

  @override
  String get dashBiggestCategory => 'Biggest category';

  @override
  String get dashTransactions => 'Transactions';

  @override
  String get dashNoIncome => 'No income this period';

  @override
  String get dashNetWorthCaption => 'Everything you own, minus what you owe';

  @override
  String get dashSpendingByCategory => 'Spending by category';

  @override
  String get dashRecent => 'Recent';

  @override
  String get dashNetThisPeriod => 'Net this period';

  @override
  String get dashTotalEarned => 'Total earned';

  @override
  String get dashTotalSpent => 'Total spent';

  @override
  String get dashGroups => 'Groups';

  @override
  String get dashAll => 'All';

  @override
  String get dashViewInReports => 'View in Reports';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authSignInSubtitle => 'Sign in to your CoinCompass';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authName => 'Name';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authStaySignedIn => 'Stay signed in';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authOrContinueWith => 'or continue with';

  @override
  String get authGoogle => 'Google';

  @override
  String get authHaveAccount => 'Already have an account?';

  @override
  String get authCreateAccount => 'Create your account';

  @override
  String get authSignUpSubtitle => 'Start tracking your money';

  @override
  String get authResetTitle => 'Reset your password';

  @override
  String get authSendResetLink => 'Send reset link';

  @override
  String get authResetSent => 'Check your inbox for the reset link.';

  @override
  String get authBackToSignIn => 'Back to sign in';

  @override
  String get authTwoFactorTitle => 'Two-factor authentication';

  @override
  String get authTwoFactorSubtitle =>
      'Enter the 6-digit code from your authenticator app';

  @override
  String get authTwoFactorCode => 'Authentication code';

  @override
  String get authUseBackupCode => 'Use a backup code instead';

  @override
  String get authUseAuthCode => 'Use an authenticator code instead';

  @override
  String get authEmailCode => 'Email me a code';

  @override
  String get authVerify => 'Verify';

  @override
  String get authOauthComingSoon => 'Google sign-in is coming soon on mobile.';

  @override
  String get emptyNoData => 'Nothing here yet';

  @override
  String get emptyNoTransactions => 'No transactions yet';

  @override
  String get emptyNoAccounts => 'No accounts yet';

  @override
  String get emptyComingNext => 'Coming next';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorGeneric => 'Please try again.';

  @override
  String get errorNoConnection =>
      'No connection. Check your internet and try again.';

  @override
  String get miscLanguage => 'Language';

  @override
  String get miscTamilComingSoon => 'Tamil is coming soon.';

  @override
  String get miscLoading => 'Loading…';

  @override
  String get miscEndOfDay => 'End of day';

  @override
  String get miscAllAccounts => 'All accounts';

  @override
  String get miscQuickAdd => 'Quick add';

  @override
  String get authNoAccount => 'Don\'t have an account?';

  @override
  String get authResetSubtitle => 'We\'ll email you a reset link';

  @override
  String get settingsSecPinMustDigits => 'The PIN must be 4 to 8 digits.';

  @override
  String get settingsSecTwoPinsDontMatch => 'The two PINs don\'t match.';

  @override
  String get settingsSecChangePin => 'Change your PIN';

  @override
  String get settingsSecSetPin => 'Set a PIN';

  @override
  String get settingsSecChangePinAction => 'Change PIN';

  @override
  String get settingsSecTurnPinLock => 'Turn on PIN lock';

  @override
  String get settingsSecDataStaysExactlyAs =>
      'Your data stays exactly as it is, and this is not your password.';

  @override
  String get settingsSecChooseDigitsPinProtects =>
      'Choose 4 to 8 digits. This PIN protects CoinCompass in a browser. To lock this phone, use App lock at the top of the Security card.';

  @override
  String get settingsSecNewPin => 'New PIN';

  @override
  String get settingsSecConfirmPin => 'Confirm PIN';

  @override
  String get settingsSecPasscodeMustCharacters =>
      'The passcode must be 4 to 32 characters.';

  @override
  String get settingsSecTwoPasscodesDontMatch =>
      'The two passcodes don\'t match.';

  @override
  String get settingsSecChangePasscode => 'Change the passcode';

  @override
  String get settingsSecSetPasscode => 'Set a passcode';

  @override
  String get settingsSecChangePasscodeAction => 'Change passcode';

  @override
  String get settingsSecLockNetWorth => 'Lock Net Worth';

  @override
  String get settingsSecNetWorthSavingsInvestments =>
      'Net Worth, Savings & Investments and Stocks stay hidden until this passcode is entered. Each place you sign in asks for it separately. Keep it somewhere safe — this app cannot clear a passcode you have forgotten; you would have to remove it from CoinCompass in a browser.';

  @override
  String get settingsSecBetweenCharactersLettersDigits =>
      'Between 4 and 32 characters. Letters, digits and symbols all count. It hides the totals: your accounts, balances, loans and transactions stay visible, and so do income, expenses and cash flow.';

  @override
  String get settingsSecWealthPasscode => 'Wealth passcode';

  @override
  String get settingsSecHide => 'Hide';

  @override
  String get settingsSecShow => 'Show';

  @override
  String get settingsSecConfirmPasscode => 'Confirm passcode';

  @override
  String get settingsProfileSigned => 'Not signed in';

  @override
  String get settingsProfileSignAgainSeeAccount =>
      'Sign in again to see your account details.';

  @override
  String get settingsProfileAccount => 'Your account';

  @override
  String get settingsProfileVerified => 'Verified';

  @override
  String get settingsProfileUnverified => 'Unverified';

  @override
  String get settingsProfileWealthView => 'Wealth view';

  @override
  String get settingsProfileEmailPassword => 'Email & password';

  @override
  String get settingsProfileGoogleAccount => 'Google account';

  @override
  String get settingsPreferencesData => 'Preferences & data';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppliesInstantlySavedAccount =>
      'Applies instantly, and is saved to your account.';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsDark => 'Dark';

  @override
  String get settingsWebAppKeepsTheme =>
      'The web app keeps the theme on the device it was picked on. This app also stores it on your account so a reinstall remembers it.';

  @override
  String get settingsWalletUpdated => 'Wallet updated';

  @override
  String get settingsWallet => 'Wallet';

  @override
  String get settingsWhatWalletCalledInside =>
      'What this wallet is called inside the app.';

  @override
  String get settingsWalletName => 'Wallet name';

  @override
  String get settingsMyWallet => 'My Wallet';

  @override
  String get settingsLabel => 'Label';

  @override
  String get settingsEGPersonalFinances => 'e.g. Personal finances';

  @override
  String get settingsOptionalTagShownAlongside =>
      'An optional tag shown alongside your wallet name.';

  @override
  String get settingsSaveChanges => 'Save changes';

  @override
  String get settingsBaseCurrencyUpdated => 'Base currency updated';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsEveryAmountAppShown =>
      'Every amount in the app is shown in this currency.';

  @override
  String get settingsNoCurrencies => 'No currencies';

  @override
  String get settingsServerHasntSentCurrency =>
      'The server hasn\'t sent a currency table for this wallet, so amounts stay in the current base currency.';

  @override
  String get settingsRatesSeededServerCannot =>
      'Rates are seeded on the server and cannot be edited here — the web app has no editor for them either, and multi-currency conversion isn\'t enabled yet.';

  @override
  String get settingsBaseCurrency => 'Base currency';

  @override
  String get settingsEmailReports => 'Email reports';

  @override
  String get settingsMonthlyMidMonthSummary => 'Monthly & mid-month summary';

  @override
  String get settingsEmailedStLastMonth =>
      'Emailed on the 1st (last month) and the 15th (this month so far).';

  @override
  String get settingsSigningOut => 'Signing out…';

  @override
  String get settingsSignsOutDeviceOnly =>
      'Signs you out on this device only. Your data stays on the server.';

  @override
  String get settingsSignOut => 'Sign out?';

  @override
  String get settingsYoullNeedEmailPassword =>
      'You\'ll need your email and password to get back in.';

  @override
  String get settingsAppInfo => 'App info';

  @override
  String get settingsApp => 'App';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsBuild => 'Build';

  @override
  String get settingsLocalBuildSingleUser => 'Local build · Single user';

  @override
  String get settingsRegion => 'Region';

  @override
  String get settingsSecuritySecurity => 'Security';

  @override
  String get settingsSecurityAppLockPhone => 'App lock (this phone)';

  @override
  String get settingsSecurityCoincompassAsksFingerprintPin =>
      'CoinCompass asks for your fingerprint — or your PIN — when you open it, and again after 30 seconds away. Checked on this phone, so it works with no signal.';

  @override
  String get settingsSecurityCoincompassAsksPinWhen =>
      'CoinCompass asks for your PIN when you open it, and again after 30 seconds away. It is checked on this phone, so it works with no signal.';

  @override
  String get settingsSecurityAskPinBeforeCoincompass =>
      'Ask for a PIN before CoinCompass opens on this phone. Checked on the device, so it works offline.';

  @override
  String get settingsSecurityLockNow => 'Lock now';

  @override
  String get settingsSecurityTurnOff => 'Turn off';

  @override
  String get settingsSecuritySetUpAppLock => 'Set up app lock';

  @override
  String get settingsSecurityUnlockFingerprint => 'Unlock with fingerprint';

  @override
  String get settingsSecurityPinLockWeb => 'PIN lock (web)';

  @override
  String get settingsSecurityDigitPinAskedWhen =>
      'A 4–8 digit PIN is asked for when you open CoinCompass in a browser. The lock on this phone is the row above.';

  @override
  String get settingsSecurityAskShortPinWhen =>
      'Ask for a short PIN when you open CoinCompass in a browser.';

  @override
  String get settingsSecurityAppLockCoversPhone =>
      'The app lock covers this phone and is checked on the device, so it works with no signal. The PIN lock covers CoinCompass in a browser. The Net Worth passcode is saved on your account, but each place you sign in asks for it separately. None of them is your account password, and none of them changes your data.';

  @override
  String get settingsSecurityTurnOffAppLock => 'Turn off the app lock?';

  @override
  String get settingsSecurityAppLockTurnedOff =>
      'App lock turned off. Screenshots and the app-switcher preview work normally again.';

  @override
  String get settingsSecurityTurnOffWebPin => 'Turn off the web PIN?';

  @override
  String get settingsSecurityCoincompassStopAskingPin =>
      'CoinCompass will stop asking for a PIN when you open it in a browser. The app lock on this phone is separate and stays as it is. You can set a new web PIN at any time.';

  @override
  String get settingsSecurityPinLockTurnedOff => 'PIN lock turned off';

  @override
  String get settingsSecurityWealthLockedDescription =>
      'Net Worth, Savings & Investments and Stocks are hidden until you enter the passcode. Unlocking here unlocks them in this app only — each place you sign in unlocks separately.';

  @override
  String get settingsSecurityWealthShowingDescription =>
      'Net Worth, Savings & Investments and Stocks are showing in this app. Locking hides them here again; anywhere else you are signed in keeps its own state.';

  @override
  String get settingsSecurityHideNetWorthSavings =>
      'Hide Net Worth, Savings & Investments and Stocks behind a passcode. The passcode is saved on your account, and each place you sign in asks for it separately.';

  @override
  String get settingsSecurityLocked => 'Locked';

  @override
  String get settingsSecurityUnlocked => 'Unlocked';

  @override
  String get settingsSecurityOff => 'Off';

  @override
  String get settingsSecurityNetWorthLock => 'Net Worth lock';

  @override
  String get settingsSecurityUnlock => 'Unlock';

  @override
  String get settingsSecurityUnlockedSignNetWorth =>
      'Unlocked for this sign-in. Net Worth stays visible here until you lock it again or sign out.';

  @override
  String get settingsSecurityLockNetWorthAgain => 'Lock Net Worth again?';

  @override
  String get settingsSecurityWealthRelockWarning =>
      'Net Worth, Savings & Investments and Stocks will be hidden until the passcode is entered again in this app. Your data is not changed.';

  @override
  String get settingsSecurityLock => 'Lock';

  @override
  String get settingsSecurityNetWorthLockedApp =>
      'Net Worth locked in this app.';

  @override
  String get settingsSecurityTurnOffNetWorth => 'Turn off the Net Worth lock?';

  @override
  String get settingsSecurityWealthTurnOffWarning =>
      'Net Worth, Savings & Investments and Stocks will be visible without a passcode, in every place you sign in. The passcode is discarded and cannot be recovered.';

  @override
  String get settingsSecurityNetWorthLockTurned => 'Net Worth lock turned off.';

  @override
  String get settingsSecuritySetUpTurnFrom =>
      'Not set up. Turn it on from the web app — enrolling needs a QR scan.';

  @override
  String get settingsSecurityUnknown => 'Unknown';

  @override
  String get settingsSecurityCouldntCheckStatusJust =>
      'Couldn\'t check the status just now.';

  @override
  String get settingsSecurityChecking => 'Checking…';

  @override
  String get settingsSecurityAppLockTurnedItself =>
      'The app lock turned itself off: the saved PIN check was missing. Set it up again.';

  @override
  String settingsProfileMemberSince(String method, String month) {
    return '$method · Member since $month';
  }

  @override
  String settingsThemeNotSaved(String failure) {
    return 'Theme applied here, but not saved: $failure';
  }

  @override
  String settingsCurrencyRate(String code, String amount) {
    return '1 $code = $amount';
  }

  @override
  String settingsCurrencyCodeAndName(String code, String name) {
    return '$code — $name';
  }

  @override
  String settingsRegionSummary(String currency, String locale) {
    return '$currency · $locale';
  }

  @override
  String settingsSecurityTwoFactorOn(String fallback, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count backup codes left.',
      one: '1 backup code left.',
    );
    return 'Authenticator app is on. $fallback$_temp0';
  }

  @override
  String get settingsSecurityEmailFallbackOn => 'Email fallback is on. ';

  @override
  String get settingsSecurityOn => 'On';
}
