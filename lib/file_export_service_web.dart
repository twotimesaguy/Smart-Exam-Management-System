import 'dart:html' as html;
import 'dart:typed_data';

class FileExportService {
  FileExportService._();

  static final FileExportService instance = FileExportService._();

  Future<void> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = _safeFileName(fileName)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return sanitized.isEmpty ? 'export' : sanitized;
  }
}
