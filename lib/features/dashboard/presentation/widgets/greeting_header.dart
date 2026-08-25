import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../reports/presentation/period.dart';

/// `Good morning, Hari` + `This month · 1 Aug – 1 Sep 2026`.
class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final name = ref.watch(currentUserProvider)?.displayName ?? '';
    final range = ref.watch(periodRangeProvider);
    final greeting = greetingForHour(DateTime.now().hour);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? greeting : '$greeting, $name',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${range.label} · ${range.rangeLabel}',
          style: TextStyle(fontSize: 13.5, color: c.mutedForeground),
        ),
      ],
    );
  }
}

/// Local-clock greeting, matching the web app's three buckets.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
