import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translation_policy.dart';

/// On-device translation, shaped so a synchronous widget can use it.
///
/// ## The problem this solves
///
/// ML Kit's `translate()` is a `Future`. `Text` is synchronous. Bridging them
/// naively — a `FutureBuilder` per label — would rebuild the tree constantly and
/// paint English then Tamil on every single string, on every screen.
///
/// So this is a **synchronous cache with an asynchronous filler**:
///
///   * [lookup] never awaits. It returns the Tamil if the cache has it,
///     otherwise the English it was given, and quietly queues the string.
///   * queued strings are translated in the background; when a batch lands,
///     [notifyListeners] fires once and the tree rebuilds with Tamil.
///
/// The visible consequence, and it is unavoidable with runtime translation: a
/// string is English the first time it is ever shown, for as long as one
/// translation takes. After that it is cached for the process's lifetime.
///
/// ## What it refuses to translate
///
/// Everything [isTranslatable] rejects — figures, currency, dates, codes — and
/// everything in [glossary], which is substituted directly. See
/// `translation_policy.dart` for why that guard exists at all.
class Translator extends ChangeNotifier {
  Translator({
    TranslateLanguage source = TranslateLanguage.english,
    TranslateLanguage target = TranslateLanguage.tamil,
    @visibleForTesting OnDeviceTranslator? translator,
    @visibleForTesting OnDeviceTranslatorModelManager? models,
  }) : _source = source,
       _target = target,
       _injectedTranslator = translator,
       _models = models ?? OnDeviceTranslatorModelManager();

  final TranslateLanguage _source;
  final TranslateLanguage _target;
  final OnDeviceTranslator? _injectedTranslator;
  final OnDeviceTranslatorModelManager _models;

  OnDeviceTranslator? _translator;

  /// English → target. The only thing [lookup] reads.
  final Map<String, String> _cache = HashMap<String, String>();

  /// Strings seen but not yet translated, in first-seen order.
  final Set<String> _pending = LinkedHashSet<String>();

  bool _enabled = false;
  bool _draining = false;
  ModelState _modelState = ModelState.unknown;

  /// Whether translation is switched on. Off means [lookup] is a pass-through,
  /// which is what keeps English rendering byte-identical.
  bool get enabled => _enabled;

  ModelState get modelState => _modelState;

  /// True once the language pack is on the device and translation can work.
  bool get ready => _modelState == ModelState.downloaded;

  @visibleForTesting
  int get cachedCount => _cache.length;

  @visibleForTesting
  int get pendingCount => _pending.length;

  /// Checks whether the Tamil model is already on the device.
  ///
  /// Never downloads on its own — a ~30MB fetch is the owner's decision, not a
  /// side effect of opening Settings.
  Future<void> refreshModelState() async {
    try {
      final present = await _models.isModelDownloaded(_target.bcpCode);
      _modelState = present ? ModelState.downloaded : ModelState.absent;
    } on Object {
      // A plugin that is unavailable (a test host, an unsupported device) must
      // not take the app down. English is always a working answer.
      _modelState = ModelState.unavailable;
    }
    notifyListeners();
  }

  /// Downloads the language pack. Wi-Fi only — this is tens of megabytes.
  Future<bool> downloadModel() async {
    _modelState = ModelState.downloading;
    notifyListeners();
    try {
      final ok = await _models.downloadModel(_target.bcpCode, isWifiRequired: true);
      _modelState = ok ? ModelState.downloaded : ModelState.absent;
      notifyListeners();
      return ok;
    } on Object {
      _modelState = ModelState.unavailable;
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteModel() async {
    try {
      await _models.deleteModel(_target.bcpCode);
    } on Object {
      // Best effort; the state refresh below is what the UI actually reads.
    }
    _cache.clear();
    _pending.clear();
    await refreshModelState();
  }

  /// Turns translation on or off.
  ///
  /// Switching off clears nothing: the cache stays warm so switching back is
  /// instant, and a stale entry is impossible because the key IS the English.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_enabled) {
      _translator ??= _injectedTranslator ??
          OnDeviceTranslator(sourceLanguage: _source, targetLanguage: _target);
      unawaited(_drain());
    }
    notifyListeners();
  }

  /// The synchronous half. Returns Tamil when it is known, English otherwise.
  ///
  /// Never awaits, never throws, and never returns an empty string — a blank
  /// label collapses a layout with no visible cause.
  String lookup(String english) {
    if (!_enabled || !ready) return english;
    if (!isTranslatable(english)) return english;

    final fixed = glossary[english];
    if (fixed != null) return fixed;

    final hit = _cache[english];
    if (hit != null) return hit;

    if (_pending.add(english)) unawaited(_drain());
    return english;
  }

  /// Translates the queue, then rebuilds the tree once for the whole batch.
  Future<void> _drain() async {
    if (_draining || !_enabled || !ready) return;
    final translator = _translator;
    if (translator == null) return;

    _draining = true;
    try {
      var translatedAny = false;
      // Re-read `_pending` each pass: painting the results reveals more strings.
      while (_pending.isNotEmpty) {
        final batch = _pending.take(_batchSize).toList(growable: false);
        for (final english in batch) {
          _pending.remove(english);
          try {
            final tamil = await translator.translateText(english);
            if (tamil.trim().isNotEmpty) {
              _cache[english] = tamil;
              translatedAny = true;
            } else {
              // An empty result is a failure, not a translation. Cache the
              // English so the same string is not retried on every rebuild.
              _cache[english] = english;
            }
          } on Object {
            _cache[english] = english;
          }
        }
        if (translatedAny) {
          notifyListeners();
          translatedAny = false;
        }
      }
    } finally {
      _draining = false;
    }
  }

  static const int _batchSize = 24;

  @override
  void dispose() {
    unawaited(_translator?.close());
    super.dispose();
  }
}

/// Where the language pack is.
enum ModelState {
  /// Not asked yet.
  unknown,

  /// Supported, but the pack is not on the device.
  absent,

  downloading,

  downloaded,

  /// ML Kit could not be reached at all — an unsupported device, or a test
  /// host with no platform channel. Translation is simply off.
  unavailable,
}
