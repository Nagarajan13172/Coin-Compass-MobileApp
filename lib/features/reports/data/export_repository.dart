import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/utils/date_x.dart';

/// A CSV that has been written to the device and is ready to hand to
/// `share_plus` (`SharePlus.instance.share(ShareParams(files: [XFile(path)]))`).
class ExportedCsv {
  const ExportedCsv({
    required this.path,
    required this.fileName,
    required this.byteCount,
  });

  /// Absolute path inside the app's temp directory. Not a user-visible file —
  /// the OS may reclaim it, which is fine: it exists only to be shared.
  final String path;

  /// `coincompass-transactions-2026-08-24-INR.csv` — what the share sheet and
  /// the receiving app will call it.
  final String fileName;
  final int byteCount;
}

/// `GET /export/csv` — the only endpoint in this app that returns a file.
///
/// The web builds an `<a href="/api/export/csv?…">` and lets the browser
/// download it. That cannot work here: the session is an httpOnly cookie in
/// Dio's jar, so a `launchUrl` would open an unauthenticated browser tab and
/// get a 401. The bytes have to come back through the same client, be written
/// to disk, and be shared as a file.
///
/// Live-verified response headers:
///
///   content-type: text/csv; charset=utf-8
///   content-disposition: attachment;
///     filename="coincompass-transactions-2026-08-24-INR.csv"
///
/// Body: `Date,Type,Amount,Currency,Account,To Account,Category,Payee,Note,Tags`
/// then one row per transaction.
class ExportRepository {
  const ExportRepository(this._api);

  final ApiClient _api;

  /// Fetches the window `[from, to)` — the same half-open ISO convention every
  /// `/reports/*` call uses — and returns the file it wrote.
  ///
  /// Omit both for every transaction ever recorded (the "All transactions"
  /// item in the web's export popover sends no params at all).
  ///
  /// [baseCurrency] only names the fallback file when the server sends no
  /// `content-disposition`; it changes nothing about what is exported.
  ///
  /// Throws [ApiException] — never a raw [DioException] — for a non-2xx, a
  /// transport failure, an empty body or a failed write, so the UI can render
  /// `error.message` like it does everywhere else.
  Future<ExportedCsv> downloadCsv({
    DateTime? from,
    DateTime? to,
    String baseCurrency = 'INR',
  }) async {
    final Response<List<int>> response;
    try {
      response = await _api.dio.get<List<int>>(
        Endpoints.exportCsv,
        queryParameters: {
          if (from != null) 'from': DateX.toApi(from),
          if (to != null) 'to': DateX.toApi(to),
        },
        // NOT json: the interceptor would try to decode a CSV body and the
        // default `Accept: application/json` invites a JSON error page.
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'text/csv'},
        ),
      );
    } catch (error) {
      throw _asApiException(error);
    }

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw ApiException(
        message: 'The export came back empty. Try a wider date range.',
        statusCode: response.statusCode,
        code: 'EMPTY_EXPORT',
      );
    }

    final fileName = fileNameFrom(
      response.headers.value('content-disposition'),
      baseCurrency: baseCurrency,
    );

    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/exports');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return ExportedCsv(
        path: file.path,
        fileName: fileName,
        byteCount: bytes.length,
      );
    } on FileSystemException catch (error) {
      throw ApiException(
        message: 'Could not save the export: ${error.message}',
        code: 'EXPORT_WRITE_FAILED',
      );
    } catch (_) {
      // A missing platform channel (path_provider unavailable) would otherwise
      // reach the UI as a raw PlatformException, which no screen renders.
      throw ApiException(
        message: 'Could not save the export to this device.',
        code: 'EXPORT_WRITE_FAILED',
      );
    }
  }

  /// Same window expressed as inclusive calendar days, which is what a date
  /// picker gives you. The last day is turned into the exclusive midnight that
  /// follows it — the +1 the web applies (`addDays(parseISO(to), 1)`) and the
  /// difference between "up to 24 Aug" and "everything on 24 Aug is missing".
  Future<ExportedCsv> downloadCsvForDays({
    required DateTime firstDay,
    required DateTime lastDay,
    String baseCurrency = 'INR',
  }) => downloadCsv(
    from: DateTime(firstDay.year, firstDay.month, firstDay.day),
    to: DateTime(lastDay.year, lastDay.month, lastDay.day + 1),
    baseCurrency: baseCurrency,
  );

  /// Pulls the filename out of a `content-disposition` header, falling back to
  /// the pattern the server itself uses. Pure and static so the parsing is
  /// unit-tested without touching the network or the filesystem.
  static String fileNameFrom(
    String? contentDisposition, {
    required String baseCurrency,
    DateTime? today,
  }) {
    final raw = _rawFileName(contentDisposition);
    // Anything with a path separator in it would escape the export directory.
    final cleaned = raw?.split(RegExp(r'[\\/]')).last.trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;

    final stamp = DateX.toYmd(today ?? DateTime.now());
    final currency = baseCurrency.isEmpty ? 'INR' : baseCurrency;
    return 'coincompass-transactions-$stamp-$currency.csv';
  }

  static String? _rawFileName(String? header) {
    if (header == null || header.isEmpty) return null;
    // RFC 5987 form first: filename*=UTF-8''name.csv
    final extended = RegExp(
      r"filename\*\s*=\s*[^']*''([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (extended != null) {
      return Uri.decodeComponent(extended.group(1)!.trim());
    }
    final plain = RegExp(
      r'filename\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    return plain?.group(1)?.trim();
  }

  /// The client's interceptor rejects a non-2xx with an [ApiException] already
  /// attached; when the body is bytes it has to be decoded before the usual
  /// Zod-envelope parsing can see it.
  static ApiException _asApiException(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      // Bytes first: the interceptor's own ApiException was built from an
      // undecoded body, so its message is only the generic status text.
      final data = error.response?.data;
      if (data is List<int> && data.isNotEmpty) {
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(data));
        } catch (_) {
          decoded = null;
        }
        return ApiException.fromResponse(
          error.response?.statusCode,
          decoded ?? '',
        );
      }
      final attached = error.error;
      if (attached is ApiException) return attached;
    }
    return ApiException.from(error);
  }
}

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepository(ref.watch(apiClientProvider)),
);
