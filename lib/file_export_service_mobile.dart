import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class FileExportService {
  FileExportService._();

  static final FileExportService instance = FileExportService._();
  static const MethodChannel _channel = MethodChannel('sems/pdf_opener');

  Future<void> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final safeFileName = _safeFileName(fileName);
    final directory = await Directory.systemTemp.createTemp('sems_export_');
    final file = File('${directory.path}${Platform.pathSeparator}$safeFileName');

    await file.writeAsBytes(bytes, flush: true);
    try {
      await _channel.invokeMethod<void>('openPdf', {
        'path': file.path,
        'mimeType': mimeType,
      });
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Unable to open file.');
    }
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return sanitized.isEmpty ? 'export' : sanitized;
  }
}
