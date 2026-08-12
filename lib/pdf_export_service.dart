import 'dart:typed_data';

import 'package:flutter_application_1/file_export_service.dart';

class PdfExportService {
  PdfExportService._();

  static final PdfExportService instance = PdfExportService._();
  Future<void> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
  }) async {
    await FileExportService.instance.saveAndOpen(
      fileName: _safeFileName(fileName),
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return sanitized.endsWith('.pdf') ? sanitized : '$sanitized.pdf';
  }
}
