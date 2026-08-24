import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/lucide_map.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/money_text.dart';
import '../../domain/loan.dart';
import '../loans_providers.dart';

/// One borrowing: what is still owed, how far through it the borrower is, and
/// the three things they can do about it.
///
/// The headline is the **outstanding** balance — the number that matters when
/// deciding whether to prepay — with the original principal demoted to the
/// progress line beneath it.
class LoanCard extends StatelessWidget {
  const LoanCard({
    super.key,
    required this.loan,
    this.onEdit,
    this.onPlan,
    this.onPay,
    this.onPreclose,
  });

  final Loan loan;

  /// Tapping the card opens the edit sheet.
  final VoidCallback? onEdit;
  final VoidCallback? onPlan;
  final VoidCallback? onPay;
  final VoidCallback? onPreclose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = loan.isActive;
    final schedule = scheduleFor(loan);
    final accent = active ? c.expense : c.income;

    return AppCard(
      onTap: onEdit,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  lucideIcon(loan.type.icon, fallback: LucideIcons.landmark),
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                label: loan.status.label,
                color: active ? c.expense : c.income,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Outstanding',
            style: TextStyle(fontSize: 12, color: c.mutedForeground),
          ),
          const SizedBox(height: 2),
          // The exact figure, the way the web app states it. FittedBox is what
          // keeps a ten-figure balance on one line; compacting this to "₹2Cr"
          // would hide the very number the card exists to show. Dense rows,
          // where a label has to share the width, keep compactAbove.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              loan.outstanding,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: active ? c.expense : c.foreground,
              ),
            ),
          ),
          if (loan.principal > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: loan.progress,
                minHeight: 8,
                backgroundColor: c.secondary,
                valueColor: AlwaysStoppedAnimation<Color>(c.income),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(loan.progress * 100).round()}% paid · '
              '${Money.compact(loan.outstanding)} left of '
              '${Money.compact(loan.principal)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Add the original amount to see how much is paid off.',
              style: TextStyle(fontSize: 12.5, color: c.mutedForeground),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Fact(
                  label: 'EMI',
                  value: loan.emi > 0 ? Money.compact(loan.emi) : '—',
                ),
              ),
              Expanded(
                child: _Fact(
                  label: 'Rate',
                  value: loan.roi > 0
                      ? '${Money.percent(loan.roi, alreadyScaled: true, decimals: 2)} p.a.'
                      : '—',
                ),
              ),
              Expanded(
                child: _Fact(
                  label: 'Tenure left',
                  value: _tenureValue(schedule),
                  // The EMI cannot service the interest, so the balance never
                  // reduces — the one number here that is a warning, not a fact.
                  tone: active && !schedule.feasible && loan.outstanding > 0
                      ? c.expense
                      : null,
                  caption: active ? _etaCaption(schedule) : null,
                ),
              ),
            ],
          ),
          if (loan.interestPaid > 0 || loan.chargesPaid > 0) ...[
            const SizedBox(height: 12),
            Text(
              _paidSoFar,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
            ),
          ],
          if (active) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 10),
            // Wrap, not Row: three labelled actions do not fit 360dp in one
            // line once the labels are readable.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Action(
                  icon: LucideIcons.calculator,
                  label: 'Planner',
                  onPressed: onPlan,
                ),
                _Action(
                  icon: LucideIcons.banknote,
                  label: 'Part payment',
                  onPressed: onPay,
                ),
                _Action(
                  icon: LucideIcons.circleCheckBig,
                  label: 'Preclose',
                  onPressed: onPreclose,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// `Home · UCO`, dropping the lender when there isn't one.
  String get _subtitle {
    final lender = loan.lender?.trim();
    if (lender == null || lender.isEmpty) return loan.type.label;
    return '${loan.type.label} · $lender';
  }

  String get _paidSoFar {
    final interest = 'Interest paid ${Money.format(loan.interestPaid)}';
    if (loan.chargesPaid <= 0) return interest;
    return '$interest · charges ${Money.format(loan.chargesPaid)}';
  }

  String _tenureValue(LoanSchedule schedule) {
    if (!loan.isActive || loan.outstanding <= 0) return '—';
    if (!schedule.feasible) return 'EMI too low';
    return formatMonths(schedule.months);
  }

  String? _etaCaption(LoanSchedule schedule) {
    if (loan.outstanding <= 0) return null;
    if (!schedule.feasible) {
      return loan.emi > 0 ? 'Balance never reduces' : 'No EMI set';
    }
    final eta = payoffEtaLabel(schedule);
    return eta == null ? null : 'ETA $eta';
  }
}

/// One of the three figures under the headline.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.caption,
    this.tone,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: c.mutedForeground)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tone,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          // Two lines, not one. At 360dp each of the three columns gets 96dp,
          // and a full-month ETA ('ETA September 2056') or the infeasible
          // warning ('Balance never reduces') does not fit on one — a single
          // ellipsised line silently ate the year.
          Text(
            caption!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: c.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
