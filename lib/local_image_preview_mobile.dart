import 'dart:io';

import 'package:flutter/material.dart';

Widget buildLocalImagePreview({
  required String path,
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
}) {
  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: errorBuilder,
  );
}
