import 'dart:io';

import 'package:dio/dio.dart';

/// Single error type surfaced by [ApiClient]. Parses the backend's uniform Zod
/// envelope so forms can render per-field errors:
///
///   {"error":"Validation failed","code":"VALIDATION_FAILED",
///    "details":{"formErrors":[],"fieldErrors":{"amount":["Required"]}}}
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
    this.formErrors = const [],
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, List<String>> fieldErrors;
  final List<String> formErrors;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isValidation =>
      fieldErrors.isNotEmpty || code == 'VALIDATION_FAILED';

  /// First error for [name], or null. Feeds straight into `TextField.errorText`.
  String? fieldError(String name) {
    final list = fieldErrors[name];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  static ApiException from(Object error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      // Transport-level failures never reach the server.
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(
            message: 'The server took too long to respond. Please try again.',
            code: 'TIMEOUT',
          );
        case DioExceptionType.connectionError:
          return ApiException(
            message: 'No connection. Check your internet and try again.',
            code: 'NO_CONNECTION',
          );
        case DioExceptionType.cancel:
          return ApiException(message: 'Request cancelled', code: 'CANCELLED');
        default:
          break;
      }
      if (error.error is SocketException) {
        return ApiException(
          message: 'No connection. Check your internet and try again.',
          code: 'NO_CONNECTION',
        );
      }
      return fromResponse(error.response?.statusCode, error.response?.data);
    }

    return ApiException(message: error.toString());
  }

  /// Builds an exception from a non-2xx response body.
  static ApiException fromResponse(int? status, Object? data) {
    String? message;
    String? code;
    final fieldErrors = <String, List<String>>{};
    final formErrors = <String>[];

    if (data is Map) {
      final map = data.cast<String, dynamic>();
      // The API uses `error`; tolerate `message` too.
      final rawMessage = map['error'] ?? map['message'];
      if (rawMessage is String && rawMessage.trim().isNotEmpty) {
        message = rawMessage;
      }
      final rawCode = map['code'];
      if (rawCode is String) code = rawCode;

      final details = map['details'];
      if (details is Map) {
        final fe = details['fieldErrors'];
        if (fe is Map) {
          fe.forEach((key, value) {
            if (value is List) {
              fieldErrors['$key'] = value
                  .map((e) => '$e')
                  .where((e) => e.isNotEmpty)
                  .toList();
            } else if (value != null) {
              fieldErrors['$key'] = ['$value'];
            }
          });
        }
        final form = details['formErrors'];
        if (form is List) {
          formErrors.addAll(form.map((e) => '$e').where((e) => e.isNotEmpty));
        }
      }
    } else if (data is String && data.trim().isNotEmpty && data.length < 300) {
      message = data;
    }

    message ??= _defaultMessage(status);

    return ApiException(
      message: message,
      statusCode: status,
      code: code,
      fieldErrors: fieldErrors,
      formErrors: formErrors,
    );
  }

  static String _defaultMessage(int? status) {
    switch (status) {
      case 400:
        return 'That request was not valid.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have access to this.';
      case 404:
        return 'Not found.';
      case 409:
        return 'That conflicts with something that already exists.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
      case null:
        return 'Something went wrong. Please try again.';
      default:
        if (status >= 500) return 'The server had a problem. Please try again.';
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ' $code' : ''}): $message';
}
