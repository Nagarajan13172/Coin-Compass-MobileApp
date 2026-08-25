import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart'
    show
        BuildContext,
        Color,
        InheritedNotifier,
        Locale,
        StatelessWidget,
        StrutStyle,
        TextAlign,
        TextDirection,
        TextHeightBehavior,
        TextOverflow,
        TextScaler,
        TextSpan,
        TextStyle,
        TextWidthBasis,
        Widget;

import 'translator.dart';

/// Puts the [Translator] in scope and rebuilds its subtree when a batch of
/// translations lands.
///
/// `InheritedNotifier` is the point: every [Text] below depends on this, so one
/// `notifyListeners()` after a batch repaints exactly the widgets that show
/// text, rather than the whole app on every individual string.
class TranslationScope extends InheritedNotifier<Translator> {
  const TranslationScope({
    super.key,
    required Translator translator,
    required super.child,
  }) : super(notifier: translator);

  /// Null when no scope is mounted — a widget test that builds a bare
  /// `MaterialApp`, for instance. Callers fall back to English.
  static Translator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TranslationScope>()
      ?.notifier;
}

/// A drop-in replacement for `material.Text` that translates its content.
///
/// ## Why the app's own `Text` and not a call at every site
///
/// 552 `Text(...)` sites render nearly every string in this app — including the
/// ones written as `label:`, `title:` or `confirmLabel:`, because the widgets
/// receiving those parameters render them through a `Text` of their own.
/// Intercepting at *render* time therefore reaches what intercepting at *call*
/// time would have needed 1,775 edits to cover.
///
/// The exceptions are the handful of Flutter properties that take a `String`
/// and build their own paragraph: `hintText`, `errorText`, `tooltip`,
/// `semanticLabel`. Those are translated explicitly where they are set — see
/// `AppTextField` — because nothing below them is a `Text`.
///
/// Reached by importing `core/ui.dart` instead of `package:flutter/material.dart`,
/// which re-exports Material with `Text` hidden and this one in its place.
///
/// Const-constructible, so every existing `const Text(...)` still compiles.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  /// Rich text is passed straight through untranslated: its content is a tree
  /// of spans assembled by the caller, and translating the pieces separately
  /// would reorder words that only make sense together.
  const Text.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    if (textSpan != null) {
      return m.Text.rich(
        textSpan!,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }

    final english = data ?? '';
    final translated = TranslationScope.maybeOf(context)?.lookup(english) ?? english;

    return m.Text(
      translated,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      // Screen readers should hear what is on screen. When the caller supplied
      // its own label that wins, as it does in Material.
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// Translates a bare string — for the few Flutter properties that take a
/// `String` and render it themselves, where there is no [Text] to intercept.
String tr(BuildContext context, String? english) {
  if (english == null || english.isEmpty) return english ?? '';
  return TranslationScope.maybeOf(context)?.lookup(english) ?? english;
}
