import 'dart:typed_data';
import 'package:epub_reader/parseEpub.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter/widgets.dart' as flutter;

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

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: SelectableText('Error: ${snapshot.error}')),
          );
        }

        final book = snapshot.data!;
        final chapters = getFlattenedChapters(book);

        return Scaffold(
          appBar: AppBar(title: Text(book.Title ?? 'Unknown Title')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Html(
              data: buildFullHtml(chapters),
            ),
          ),
        );

      },
    );
  }

  // temporary solution to build entire HTML content from all chapters
  String buildFullHtml(List<EpubChapter> chapters) {
    final parts = <String>[];

    for (final chapter in chapters) {
      final html = chapter.HtmlContent;
      if (html == null || html.isEmpty) continue;
      parts.add(html);
    }

    return parts.join();
  }


  // flatten any nested sub-chapters into a single list
  List<EpubChapter> getFlattenedChapters(EpubBook book) {
    List<EpubChapter> result = [];

    void recurse(List<EpubChapter>? chapters) {
      if (chapters == null) return; // base case

      for (var chapter in chapters) {
        result.add(chapter); // add the current chapter
        if (chapter.SubChapters!.isNotEmpty) {
          recurse(chapter.SubChapters); // add nested chapters recursively
        }
      }
    }

    recurse(book.Chapters);
    return result;
  }
}
