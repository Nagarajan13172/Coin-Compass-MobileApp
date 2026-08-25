/// Phase 7.3c — getting a file off the phone and into a `String`.
///
/// Behind a provider for the same reason `csvSharerProvider` is: `file_picker`
/// talks to a method channel that does not exist under `flutter test`, so a
/// widget test that taps "Choose a file" would blow up inside the plugin
/// rather than exercising the screen. Tests override this with a fake that
/// returns canned CSV text.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the user chose, already decoded.
class PickedCsv {
  const PickedCsv({
    required this.name,
    required this.text,
    required this.byteCount,
  });

  final String name;
  final String text;
  final int byteCount;
}

/// Thrown for a file this app will not read. The message goes straight to the
/// screen, so each one says what to do rather than what went wrong.
class CsvPickException implements Exception {
  const CsvPickException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Returns null when the user backs out of the picker, which is not an error.
typedef CsvPicker = Future<PickedCsv?> Function();

/// Refused above this. A CSV of transactions is a few hundred KB at the very
/// most; anything past 8MB is a different kind of file, and reading it would
/// mean holding the text, the parsed table and every row model in memory at
/// once on a phone.
const int maxCsvBytes = 8 * 1024 * 1024;

final csvPickerProvider = Provider<CsvPicker>((ref) => pickCsvFromDevice);

Future<PickedCsv?> pickCsvFromDevice() async {
  final PlatformFile? file;
  try {
    file = await FilePicker.pickFile(
      dialogTitle: 'Choose a CSV to import',
      type: FileType.custom,
      // `txt` because plenty of banks hand out a CSV named `.txt`, and the
      // Android picker filters strictly by extension.
      allowedExtensions: const ['csv', 'txt'],
    );
  } catch (error) {
    throw CsvPickException('Could not open the file picker: $error');
  }

  // Null is the user backing out of the picker, which is not an error.
  if (file == null) return null;

  // Size is checked *before* the bytes are read. `readAsBytes` on a file the
  // user picked by mistake — a video, a database dump — would otherwise pull
  // the whole thing into memory just to reject it.
  final length = await file.length();
  if (length == 0) {
    throw const CsvPickException('That file is empty.');
  }
  if (length > maxCsvBytes) {
    throw CsvPickException(
      'That file is ${(length / (1024 * 1024)).toStringAsFixed(1)}MB. '
      'The importer reads files up to '
      '${(maxCsvBytes / (1024 * 1024)).round()}MB.',
    );
  }

  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (error) {
    throw const CsvPickException(
      'That file could not be read from this device. Try copying it into '
      'your Downloads folder first.',
    );
  }

  return PickedCsv(
    name: file.name,
    text: decodeCsvBytes(bytes),
    byteCount: bytes.length,
  );
}

/// UTF-8, falling back to Latin-1.
///
/// A spreadsheet saved as "CSV" on a Windows machine is frequently
/// Windows-1252, in which a rupee sign or a smart quote is a byte UTF-8 will
/// reject. Decoding strictly and then falling back keeps a valid UTF-8 file
/// exact — which matters for Tamil payee names — while still reading the
/// legacy file instead of refusing it. Latin-1 cannot fail, so there is no
/// third case.
///
/// `allowMalformed` is deliberately **not** used on the first pass: it would
/// replace the bad bytes with U+FFFD and succeed, so the fallback would never
/// run and the user would import payees full of question marks.
String decodeCsvBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}
