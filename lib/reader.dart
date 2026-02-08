import 'dart:typed_data';
import 'package:epub_reader/parseEpub.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class Cfi {
  final int spineIndex;
  final List<int> path; // DOM path inside the XHTML
  final int charOffset; // offset inside text node

  Cfi(this.spineIndex, this.path, this.charOffset);
}

class BookIndex {
  final Map<String, List<Cfi>> index = {};

  Future<void> build(EpubBook book) async {
    index.clear();


  }
}

class Reader extends StatefulWidget {
  final Uint8List bytes;

  const Reader({super.key, required this.bytes});

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  final BookIndex bookIndex = BookIndex();
  late Future<EpubBook> _bookFuture;

  @override
  void initState() {
    super.initState();
    _bookFuture = _loadAndIndex();
  }

  Future<EpubBook> _loadAndIndex() async {
    final book = await parseEpub(widget.bytes);
    await bookIndex.build(book);
    return book;
  }

  @override
  Widget build(BuildContext context) {
    // load and parse the epub file in the background,
    // show a loading indicator while waiting. This is useful for large files.
    return FutureBuilder<EpubBook>(
      future: _bookFuture,
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
