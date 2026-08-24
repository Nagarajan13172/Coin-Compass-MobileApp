import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_exception.dart';
import 'empty_state.dart';

/// Uniform failure surface. Reads the message straight off [ApiException] so the
/// backend's own copy is shown when it has something useful to say.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final offline = api?.code == 'NO_CONNECTION';

    return EmptyState(
      icon: offline ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      title: offline ? 'No connection' : 'Something went wrong',
      message: api?.message ?? 'Please try again.',
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
      compact: compact,
    );
  }
}
