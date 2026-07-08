import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';

class DownloadsSaver {
  static const _channel = MethodChannel('downloads_saver');

  static Future<String?> saveHtml({
    required String fileName,
    required String html,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(html));

    final path = await _channel.invokeMethod<String>(
      'saveToDownloads',
      {
        'name': fileName,
        'bytes': bytes,
        'mimeType': 'text/html',
      },
    );

    return path;
  }
}