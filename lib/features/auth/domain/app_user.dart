import '../../../core/api/json.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.name = '',
    this.avatarUrl = '',
    this.emailVerified = false,
    this.hasPassword = true,
    this.twoFactorEnabled = false,
    this.mode = 'user',
    this.wealthLockEnabled = false,
    this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String avatarUrl;
  final bool emailVerified;
  final bool hasPassword;
  final bool twoFactorEnabled;
  final String mode;
  final bool wealthLockEnabled;
  final DateTime? createdAt;

  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  /// Two letters for the app-bar avatar, e.g. "HA" for "Hari".
  String get initials {
    final source = name.trim().isNotEmpty ? name.trim() : email;
    final parts = source.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final one = parts.first;
      return (one.length >= 2 ? one.substring(0, 2) : one).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // /auth/signin and /auth/me both wrap the user; callers may pass either the
    // envelope or the inner object.
    final source = json['user'] is Map ? J.map(json['user']) : json;
    return AppUser(
      id: J.str(source['id'] ?? source['_id']),
      email: J.str(source['email']),
      name: J.str(source['name']),
      avatarUrl: J.str(source['avatarUrl']),
      emailVerified: J.boolean(source['emailVerified']),
      hasPassword: J.boolean(source['hasPassword'], true),
      twoFactorEnabled: J.boolean(source['twoFactorEnabled']),
      mode: J.str(source['mode'], 'user'),
      wealthLockEnabled: J.boolean(source['wealthLockEnabled']),
      createdAt: J.date(source['createdAt']),
    );
  }
}
