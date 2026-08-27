import 'dart:typed_data';

class FileExportService {
  FileExportService._();

  static final FileExportService instance = FileExportService._();

  Future<void> saveAndOpen({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    throw UnsupportedError('File export is not supported on this platform.');
  }
}
