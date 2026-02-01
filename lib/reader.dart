import 'dart:typed_data';
import 'package:epub_reader/parseEpub.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';

class Reader extends StatelessWidget {
  final Uint8List bytes;

  const Reader({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    // load and parse the epub file in the background,
    // show a loading indicator while waiting. This is useful for large files.
    return FutureBuilder<EpubBook>(
      future: parseEpub(bytes),
      builder: (context, snapshot) {
        // loading indicator
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final book = snapshot.data!;
        return Scaffold(
          appBar: AppBar(title: Text(book.Title ?? 'Unknown Title')),
          body: Center(child: Text('book loaded')),
        );
      },
    );
  }
}
