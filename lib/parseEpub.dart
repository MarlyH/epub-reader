import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';

Future<EpubBook> parseEpub(Uint8List bytes) {
  return compute(_parseEpubIsolate, bytes);
}

Future<EpubBook> _parseEpubIsolate(Uint8List bytes) {
  return EpubReader.readBook(bytes);
}
