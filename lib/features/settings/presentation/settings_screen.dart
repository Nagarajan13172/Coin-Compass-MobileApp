import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';
import 'profile_card.dart';
import 'security_card.dart';
import 'settings_providers.dart';
import '../../../core/router/route_refresh.dart';
import '../../../l10n/app_localizations.dart';

/// `/settings` — who is signed in, how the app looks, what the wallet is
/// called, which currency it counts in, and the two locks that guard it.
///
/// Body only; [AppScaffold] supplies the chrome.
///
/// ## What is deliberately not here
///
/// * **`firstDayOfWeek` / `monthStartDay`.** Both come back from
///   `GET /settings`, and both appear **zero** times in the deployed web
///   bundle — no web control writes them, so their Zod status on a write is
///   unknown. A mobile control would be writing an unverified key into a live
///   account, which is exactly how this project has lost data before. They are
///   read (the week window uses `firstDayOfWeek`) and never written.
/// * **A currency editor.** `rateToBase` has zero hits in the bundle: the table
///   is server-seeded and read-only everywhere in the deployed client. The rows
///   below show the rates; picking one only ever sends `{baseCurrency}`.
/// * **"Send a test report now"** (`POST /reports/email-now?kind=midmonth`).
///   It sends the owner a real email; it is on this project's never-call list.
/// * **Language.** The shell's top-bar pill already owns it, and the Tamil
///   dictionary is a later phase.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    final c = context.colors;

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.card,
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The shell's chrome overlaps the body, so the tail pads past the nav
        // bar and the raised FAB — `shellBottomInset`, not a hardcoded 110.
        padding: EdgeInsets.only(bottom: shellBottomInset(context)),
        children: [
          ScreenHeader(title: L.of(context).navSettings, subtitle: L.of(context).settingsPreferencesData),

          // Independent of /settings on purpose: a settings failure should not
          // blank out who you are signed in as, or strand you without a way to
          // change the theme or sign out.
          const _Section(child: SettingsProfileCard()),
          const _Section(child: _AppearanceCard()),

          switch (settings) {
            // `valueOrNull` rather than `AsyncData`: after a write the
            // provider is invalidated and re-enters AsyncLoading while it
            // refetches. Every card would flash into a skeleton on each toggle
            // if the loading branch won — so anything with a value in hand
            // keeps rendering, and only a cold start or a first-load failure
            // falls through. (`AsyncError.value` *rethrows*; `valueOrNull` is
            // the one that answers null.)
            AsyncValue(:final valueOrNull?) => Column(
              children: [
                _Section(child: _WalletCard(settings: valueOrNull)),
                _Section(child: _CurrencyCard(settings: valueOrNull)),
                _Section(child: _EmailReportsCard(settings: valueOrNull)),
                _Section(child: SettingsSecurityCard(settings: valueOrNull)),
              ],
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(settingsProvider),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  LoadingCard(lines: 4),
                  SizedBox(height: 12),
                  LoadingCard(lines: 4),
                  SizedBox(height: 12),
                  LoadingCard(lines: 5),
                ],
              ),
            ),
          },

          const _Section(child: _SignOutCard()),
          _Section(child: _AppInfoCard(settings: settings.valueOrNull)),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) =>
      refreshCurrentRoute(ref, '/settings');
}

/// The 20dp gutter every card on this screen sits in.
class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: child);
}

// ─── appearance ─────────────────────────────────────────────────────────────

/// Light / Dark / System. Drives [themeControllerProvider] — the same
/// [ThemeMode] `main()` hands to `MaterialApp` — and persists the choice.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeControllerProvider);
    final pending = ref.watch(settingsWriteControllerProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: L.of(context).settingsAppearance,
            subtitle: L.of(context).settingsAppliesInstantlySavedAccount,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final option in [
                (ThemeMode.system, L.of(context).settingsSystem, LucideIcons.monitor),
                (ThemeMode.light, L.of(context).settingsLight, LucideIcons.sun),
                (ThemeMode.dark, L.of(context).settingsDark, LucideIcons.moon),
              ]) ...[
                if (option.$1 != ThemeMode.system) const SizedBox(width: 8),
                Expanded(
                  child: _ThemeOption(
                    label: option.$2,
                    icon: option.$3,
                    selected: mode == option.$1,
                    busy: pending == SettingsWrite.theme && mode == option.$1,
                    onTap: pending != null
                        ? null
                        : () => _apply(context, ref, option.$1),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            L.of(context).settingsWebAppKeepsTheme,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .setTheme(mode);
    if (failure == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l.settingsThemeNotSaved(failure)),
        ),
      );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = selected ? c.primary : c.mutedForeground;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? c.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: busy
                    ? CircularProgressIndicator(strokeWidth: 2, color: tone)
                    : Icon(icon, size: 19, color: tone),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.foreground : c.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── wallet ─────────────────────────────────────────────────────────────────

/// `PUT /settings {name, description}` — both keys always travel together,
/// exactly as the web sends them.
class _WalletCard extends ConsumerStatefulWidget {
  const _WalletCard({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends ConsumerState<_WalletCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.settings.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.settings.description,
  );

  @override
  void didUpdateWidget(covariant _WalletCard old) {
    super.didUpdateWidget(old);
    // A successful save (or a pull-to-refresh) hands down a fresh document.
    // Only adopt it where the user has not typed something else, so a refetch
    // landing mid-edit cannot eat what they were writing.
    if (old.settings.name != widget.settings.name &&
        _name.text == old.settings.name) {
      _name.text = widget.settings.name;
    }
    if (old.settings.description != widget.settings.description &&
        _description.text == old.settings.description) {
      _description.text = widget.settings.description;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != widget.settings.name ||
      _description.text.trim() != widget.settings.description;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .saveWallet(name: _name.text, description: _description.text);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure ?? l.settingsWalletUpdated)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final c = context.colors;
    final busy =
        ref.watch(settingsWriteControllerProvider) == SettingsWrite.wallet;
    final blocked = ref.watch(settingsWriteControllerProvider) != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l.settingsWallet,
            subtitle: l.settingsWhatWalletCalledInside,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: l.settingsWalletName,
            hint: l.settingsMyWallet,
            controller: _name,
            enabled: !blocked,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: l.settingsLabel,
            hint: l.settingsEGPersonalFinances,
            controller: _description,
            enabled: !blocked,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => (_dirty && !blocked) ? _save() : null,
          ),
          const SizedBox(height: 8),
          Text(
            l.settingsOptionalTagShownAlongside,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: l.settingsSaveChanges,
              expand: false,
              busy: busy,
              // Empty names are refused before the request is built — the web
              // toasts and sends nothing, and so does the repository.
              onPressed: (!_dirty || blocked || _name.text.trim().isEmpty)
                  ? null
                  : _save,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── currency ───────────────────────────────────────────────────────────────

/// The server-seeded currency table. Tapping a row sends `{baseCurrency}` and
/// nothing else; the rates themselves are read-only.
class _CurrencyCard extends ConsumerStatefulWidget {
  const _CurrencyCard({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_CurrencyCard> createState() => _CurrencyCardState();
}

class _CurrencyCardState extends ConsumerState<_CurrencyCard> {
  /// Which row is waiting on its own write, so only that one spins.
  String? _pendingCode;

  Future<void> _select(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    setState(() => _pendingCode = code);
    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .setBaseCurrency(code);
    if (mounted) setState(() => _pendingCode = null);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(failure ?? l.settingsBaseCurrencyUpdated)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final c = context.colors;
    final settings = widget.settings;
    final currencies = settings.currencies;
    final blocked = ref.watch(settingsWriteControllerProvider) != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l.settingsCurrency,
            subtitle: l.settingsEveryAmountAppShown,
          ),
          const SizedBox(height: 6),
          if (currencies.isEmpty)
            EmptyState(
              compact: true,
              icon: LucideIcons.coins,
              title: l.settingsNoCurrencies,
              message:
                  l.settingsServerHasntSentCurrency,
            )
          else
            for (var i = 0; i < currencies.length; i++) ...[
              if (i > 0) Divider(color: c.border, height: 1),
              _CurrencyRow(
                currency: currencies[i],
                base: settings.baseCurrency,
                baseSymbol: settings.symbol,
                busy: _pendingCode == currencies[i].code,
                onTap: (blocked || currencies[i].code == settings.baseCurrency)
                    ? null
                    : () => _select(currencies[i].code),
              ),
            ],
          const SizedBox(height: 10),
          Text(
            l.settingsRatesSeededServerCannot,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.currency,
    required this.base,
    required this.baseSymbol,
    required this.busy,
    required this.onTap,
  });

  final CurrencyOption currency;
  final String base;
  final String baseSymbol;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final c = context.colors;
    final selected = currency.code == base;
    final rate = selected
        ? l.settingsBaseCurrency
        : l.settingsCurrencyRate(
            currency.code,
            Money.format(currency.rateToBase, symbol: baseSymbol),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (selected ? c.primary : c.mutedForeground).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  currency.symbol.isEmpty ? currency.code : currency.symbol,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: selected ? c.primary : c.mutedForeground,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.of(
                        context,
                      ).settingsCurrencyCodeAndName(currency.code, currency.name),
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rate,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                height: 22,
                child: busy
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.primary,
                      )
                    : selected
                    ? Icon(LucideIcons.check, size: 19, color: c.primary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── email reports ──────────────────────────────────────────────────────────

/// `PUT /settings {emailReports}`.
///
/// The web pairs this with a "Send a test report now" button
/// (`POST /reports/email-now?kind=midmonth`). That one sends the owner a real
/// email and is on this project's never-call list, so it is not built here.
class _EmailReportsCard extends ConsumerWidget {
  const _EmailReportsCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pending = ref.watch(settingsWriteControllerProvider);
    final busy = pending == SettingsWrite.emailReports;

    Future<void> toggle(bool value) async {
      final messenger = ScaffoldMessenger.of(context);
      final failure = await ref
          .read(settingsWriteControllerProvider.notifier)
          .setEmailReports(value);
      if (failure == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: L.of(context).settingsEmailReports),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.of(context).settingsMonthlyMidMonthSummary,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      L.of(context).settingsEmailedStLastMonth,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 34,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.primary,
                          ),
                        )
                      : Switch(
                          value: settings.emailReports,
                          onChanged: pending != null ? null : toggle,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── sign out ───────────────────────────────────────────────────────────────

/// `POST /auth/logout` behind a confirmation, followed by a cookie-jar wipe.
class _SignOutCard extends ConsumerWidget {
  const _SignOutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pending = ref.watch(settingsWriteControllerProvider);
    final busy = pending == SettingsWrite.signOut;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: pending != null ? null : () => _confirm(context, ref),
            icon: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.destructive,
                    ),
                  )
                : const Icon(LucideIcons.logOut, size: 18),
            label: Text(busy ? L.of(context).settingsSigningOut : L.of(context).authSignOut),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.destructive,
              side: BorderSide(color: c.destructive.withValues(alpha: 0.4)),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            L.of(context).settingsSignsOutDeviceOnly,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.settingsSignOut,
      message: l.settingsYoullNeedEmailPassword,
      confirmLabel: l.authSignOut,
    );
    if (!confirmed) return;

    // The router redirects to /login the moment auth state flips, so there is
    // nothing to navigate here.
    final failure = await ref
        .read(settingsWriteControllerProvider.notifier)
        .signOut();
    if (failure == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure)));
  }
}

// ─── app info ───────────────────────────────────────────────────────────────

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard({required this.settings});

  final AppSettings? settings;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final c = context.colors;
    final region = settings == null
        ? '—'
        : L.of(
            context,
          ).settingsRegionSummary(settings!.baseCurrency, settings!.locale);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: l.settingsAppInfo),
          const SizedBox(height: 10),
          for (final row in [
            (l.settingsApp, l.appName),
            (l.settingsVersion, _version),
            (l.settingsBuild, l.settingsLocalBuildSingleUser),
            (l.settingsRegion, region),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.$1,
                    style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
                  ),
                  const SizedBox(width: 16),
                  // Flexible + wrapping, not ellipsis: a trimmed build string
                  // is a support ticket nobody can answer.
                  Flexible(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Hardcoded in the web client too (`const RJ = "1.0.0"`).
  static const String _version = '1.0.0';
}
