# Coin-Compass-MobileApp

CoinCompass — a personal finance manager built with Flutter.

Track transactions, budgets, goals, loans, splits, and investments (stocks &
metals) against the CoinCompass backend API.

## Stack

| Concern    | Package |
| ---------- | ------- |
| State      | `flutter_riverpod` |
| Networking | `dio` + `dio_cookie_manager` (cookie-based session auth) |
| Routing    | `go_router` |
| Charts     | `fl_chart` |
| Icons      | `lucide_icons_flutter` |
| Storage    | `shared_preferences`, `path_provider` |
| Security   | `local_auth` (biometric unlock) |

## Getting started

```bash
flutter pub get
flutter run
```

Requires the Flutter SDK matching `environment.sdk: ^3.12.0` in
[pubspec.yaml](pubspec.yaml).

## Project layout

```
lib/
  core/       api client, theme, router, i18n, shared widgets, utils
  features/   feature modules (auth, transactions, budgets, …)
  main.dart
assets/       fonts (Inter) and i18n bundles
docs/         SPEC.md and ROADMAP.md
test/         unit tests + JSON fixtures
```

## Tests

```bash
flutter test
```

## Docs

- [Specification](docs/SPEC.md)
- [Roadmap](docs/ROADMAP.md)
