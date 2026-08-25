import '../ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/import/presentation/import_screen.dart';
import '../../features/_placeholder/placeholder_screen.dart';
import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/two_factor_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/credits/presentation/credits_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/gold/presentation/gold_screen.dart';
import '../../features/holdings/presentation/holdings_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/loans/presentation/loans_screen.dart';
import '../../features/networth/presentation/net_worth_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/people/presentation/people_screen.dart';
import '../../features/recurring/presentation/recurring_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splits/presentation/splits_screen.dart';
import '../../features/stocks/presentation/stocks_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../features/wealth_lock/domain/wealth_lock.dart';
import '../../features/wealth_lock/presentation/wealth_gate.dart';
import '../../features/wealth_lock/presentation/wealth_lock_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/app_scaffold.dart';
import 'destinations.dart';

/// Routes reachable without a session.
const Set<String> _authRoutes = {
  '/login',
  '/login/2fa',
  '/signup',
  '/forgot-password',
  '/reset-password',
  '/verify-email',
};

bool _isAuthRoute(String location) =>
    _authRoutes.any((r) => location == r || location.startsWith('$r?'));

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN WIRING — swap a PlaceholderScreen for the real screen as each feature
// lands. Everything else (shell, nav, redirects) stays untouched.
// ─────────────────────────────────────────────────────────────────────────────
Widget _screenFor(Destination d) => switch (d.path) {
  // phase 2 — shipped
  '/' => const DashboardScreen(),
  '/transactions' => const TransactionsScreen(),
  '/accounts' => const AccountsScreen(),
  '/categories' => const CategoriesScreen(),
  // phase 3 — shipped
  '/budgets' => const BudgetsScreen(),
  '/goals' => const GoalsScreen(),
  '/recurring' => const RecurringScreen(),
  '/calendar' => const CalendarScreen(),
  '/credits' => const CreditsScreen(),
  // phase 4 — shipped. The two wealth screens are wrapped, not just
  // redirected: see [_wealthGated].
  '/net-worth' => _wealthGated((_) => const NetWorthScreen()),
  '/loans' => const LoansScreen(),
  '/stocks' => _wealthGated((_) => const StocksScreen()),
  '/gold' => const GoldScreen(),
  // phase 5 — shipped
  '/reports' => const ReportsScreen(),
  '/insights' => const InsightsScreen(),
  '/notifications' => const NotificationsScreen(),
  '/settings' => const SettingsScreen(),
  _ => PlaceholderScreen(title: d.label, icon: d.icon),
};

/// Phase 6.2 — the render-level half of the Net Worth gate.
///
/// The redirect below already sends a locked user home, but a redirect acts a
/// frame late: `GoRouter` builds, then redirects. Wrapping the screen means the
/// widget is never constructed while locked, so its providers never fire
/// `/networth/history`, `/holdings` or `/stocks/portfolio`, and there is no
/// frame of the owner's money to leak on a deep link. Same argument 6.1 used
/// for putting the app lock above the Router instead of trusting a redirect.
Widget _wealthGated(WidgetBuilder builder) =>
    WealthGate(checking: const WealthCheckingScreen(), builder: builder);

/// Bridges Riverpod auth state into GoRouter so redirects re-run on sign-in
/// and sign-out.
///
/// It also has to fire when the **wealth lock flag** flips, not only when the
/// session status does: unlocking does not change `AuthStatus`, so without this
/// the gated redirect would never re-run and an owner who has just unlocked
/// would still be bounced off `/net-worth`.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status != next.status ||
          previous?.user?.wealthLockEnabled != next.user?.wealthLockEnabled ||
          previous?.user?.mode != next.user?.mode) {
        notifyListeners();
      }
    }, fireImmediately: false);
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Session not resolved yet — hold on the splash, never redirect.
      if (!auth.isResolved) return null;

      if (auth.status == AuthStatus.needsTwoFactor) {
        return location == '/login/2fa' ? null : '/login/2fa';
      }

      if (!auth.isSignedIn) {
        return _isAuthRoute(location) ? null : '/login';
      }

      // Signed in but sitting on an auth screen — go home.
      if (_isAuthRoute(location)) return '/';

      // The Net Worth gate. Web parity, verbatim:
      //   function GJ(){ return no() ? <Md/> : <Navigate to="/" replace/> }
      //
      // Keyed on `locked` only, never on `checking`: a resume re-reads
      // /auth/me, and kicking an unlocked owner off the screen they were
      // reading every time the app comes back would be its own bug. While
      // `checking` the WealthGate wrapper shows a placeholder instead of a
      // figure, which is the part that matters.
      //
      // Deliberately a pure function of location + visibility, with no
      // provider writes inside it — a redirect that mutates state re-enters
      // itself.
      if (isWealthGatedPath(location) &&
          ref.read(wealthVisibilityProvider) == WealthVisibility.locked) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/login/2fa', builder: (_, _) => const TwoFactorScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppScaffold(location: state.matchedLocation, child: child),
        routes: [
          for (final d in appDestinations)
            GoRoute(path: d.path, builder: (_, _) => _screenFor(d)),
          // Credits' own sub-screens. They live under /credits so the bottom
          // nav keeps "More" lit, and they are reached from that screen rather
          // than from the nav — the web app has no separate entry for either.
          GoRoute(
            path: '/credits/people',
            builder: (_, _) => const PeopleScreen(),
          ),
          GoRoute(
            path: '/credits/splits',
            builder: (_, _) => const SplitsScreen(),
          ),
          // 7.3 — CSV import. Under /reports for the same reason People and
          // Splits sit under /credits: the bottom nav keeps Reports lit, and
          // the screen is reached from Reports' own header rather than from
          // the nav. The web app has a top-level /import; this app has no nav
          // slot to spare for it.
          GoRoute(
            path: ImportScreen.routePath,
            builder: (_, _) => const ImportScreen(),
          ),
          // Holdings has no nav slot of its own — the sidebar has exactly 17
          // destinations and the web app reaches savings & investments from
          // Net Worth. Mounting it under /net-worth keeps that entry lit.
          // Gated with the other two. The web has no /holdings route at all —
          // it renders holdings inside /net-worth — but it drops the
          // `holdings` query key on every lock and unlock, and its settings
          // copy names what is hidden as "Net Worth (holdings & net-worth
          // totals)". An open route here would be a hole straight through the
          // gate.
          GoRoute(
            path: HoldingsScreen.routePath,
            builder: (_, _) => _wealthGated((_) => const HoldingsScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.path),
  );
});

/// Shown while the persisted session cookie is being validated.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                LucideIcons.compass,
                size: 30,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'CoinCompass',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: c.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '404',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Page not found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              location,
              style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/'),
              style: FilledButton.styleFrom(minimumSize: const Size(190, 46)),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
