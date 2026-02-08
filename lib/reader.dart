import 'dart:typed_data';
import 'package:epub_reader/parseEpub.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:xml/xml.dart';

// this is a temporary class for our in-memory index.
// In reality, this needs to be to and from an actual CFI string for
// persistent storage in a db or whatever.
class Cfi {
  // chapter index in book e.g. 0 for first chapter
  final int spineIndex;

  // DOM path inside the XHTML e.g. [0, 2, 4] means:
  // root -> first child (0) -> third child (2) -> fifth child (4)
  final List<int> path;

  // defines starting character for the selected word in selected node
  // e.g. if the text node is "Hello world" and the word is "world",
  // the charOffset would be 6
  final int charOffset;

  Cfi(this.spineIndex, this.path, this.charOffset);
}

class BookIndex {
  final Map<String, List<Cfi>> index = {};

  static final RegExp _wordRegex = RegExp(r"[A-Za-z0-9']+");
  static const int _maxOccurrencesPerWord = 200;

  /// Build the in-memory search index from an EPUB book.
  Future<void> build(EpubBook book) async {
    index.clear();

    final allChapters = _getAllChaptersFlattened(book);

    for (int chapterIndex = 0; chapterIndex < allChapters.length; chapterIndex++) {
      final chapter = allChapters[chapterIndex];
      final htmlContent = chapter.HtmlContent;
      if (htmlContent == null || htmlContent.isEmpty) continue;

      try {
        // Wrap in <body> because the HTML fragment may not have a root
        final document = XmlDocument.parse('<body>$htmlContent</body>');
        _walkElementTree(
          currentElement: document.rootElement,
          chapterIndex: chapterIndex,
          currentPath: [],
        );
      } catch (e) {
        debugPrint('Failed to parse chapter "${chapter.Title}": $e');
      }
    }

    debugPrint('Index built: ${index.length} unique words');
  }

  /// Recursively walk the XML element tree until we find a text node we can index.
  void _walkElementTree({
    required XmlElement currentElement,
    required int chapterIndex,
    required List<int> currentPath,
  }) {
    int elementPosition = 0;

    for (final child in currentElement.children) {
      if (child is XmlElement) {
        final tagName = child.name.local;
        if (tagName == 'script' || tagName == 'style') continue;

        // Recurse into this element, adding its position to the path
        _walkElementTree(
          currentElement: child,
          chapterIndex: chapterIndex,
          currentPath: [...currentPath, elementPosition * 2],
        );
        elementPosition++;
      } else if (child is XmlText) {
        _indexTextNode(
          textContent: child.text,
          chapterIndex: chapterIndex,
          elementPath: currentPath,
        );
      }
    }
  }

  /// Splits a text node into words and stores CFIs in the index.
  void _indexTextNode({
    required String textContent,
    required int chapterIndex,
    required List<int> elementPath,
  }) {
    for (final match in _wordRegex.allMatches(textContent)) {
      final word = match.group(0)!.toLowerCase();

      final postingsList = index.putIfAbsent(word, () => []);
      if (postingsList.length >= _maxOccurrencesPerWord) continue;

      postingsList.add(
        Cfi(
          chapterIndex,
          List<int>.from(elementPath),
          match.start,
        ),
      );
    }
  }

  /// Flattens all chapters and subchapters into a single list in reading order.
  List<EpubChapter> _getAllChaptersFlattened(EpubBook book) {
    final result = <EpubChapter>[];

    void flattenChapters(List<EpubChapter>? chapters) {
      if (chapters == null) return;

      for (final chapter in chapters) {
        result.add(chapter);
        if (chapter.SubChapters!.isNotEmpty) {
          flattenChapters(chapter.SubChapters);
        }
      }
    }

    flattenChapters(book.Chapters);
    return result;
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
        final chapters = bookIndex._getAllChaptersFlattened(book);

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
}
