import 'package:flutter/material.dart';

Widget buildLocalImagePreview({
  required String path,
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
}) {
  return Image.network(path, fit: fit, errorBuilder: errorBuilder);
}
