import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:epub_reader/parseEpub.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:xml/xml.dart';
import 'data/library_database.dart';

late final String bookId;
final LibraryDatabase db = LibraryDatabase();

class BookIndex {
  final Map<String, List<String>> wordCfiMap = {};

  static final RegExp _wordRegex = RegExp(r"[A-Za-z0-9'’]+");

  Future<void> build(EpubBook book) async {

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

    db.insertWordOccurrencesBatch(bookId, wordCfiMap);
    debugPrint('Index built: ${wordCfiMap.length} unique words');
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
          currentPath: [...currentPath, elementPosition * 2 + 2],
          // follow CFI spec for element positions. See:
          // https://idpf.org/epub/linking/cfi/#sec-path-child-ref
          // "Child [XML] elements are assigned even indices
          // (i.e., starting at 2, followed by 4, etc.). "
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
  Future<void> _indexTextNode({
    required String textContent,
    required int chapterIndex,
    required List<int> elementPath,
  }) async {
    for (final match in _wordRegex.allMatches(textContent)) {
      final word = match.group(0)!.toLowerCase();

      // build a string representation of each CFI
      final pathString = elementPath.map((e) => '/$e').join();
      final cfiString = '/$chapterIndex!$pathString/1:${match.start}';
      debugPrint('Indexed word "$word" -> CFI: $cfiString');

      // store the CFI string in the map for this word
      final cfiList = wordCfiMap.putIfAbsent(word, () => []);
      cfiList.add(cfiString);
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
  final PlatformFile epubFile;

  const Reader({super.key, required this.epubFile});

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  final BookIndex bookIndex = BookIndex();
  late Future<EpubBook> _bookFuture;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bookFuture = _loadAndIndex();
  }

  Future<EpubBook> _loadAndIndex() async {
    final path = widget.epubFile.path!;
    final bytes = widget.epubFile.bytes ?? await File(path).readAsBytes();
    bookId = sha256.convert(bytes).toString();
    EpubBook book = await parseEpub(bytes);

    bool inserted = await db.insertBook(bookId, book.Title, path);

    // build the index after inserting a new book
    if (inserted) {
      debugPrint('New book added: ${book.Title}, building index...');
      await bookIndex.build(book);
    }

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
          appBar: AppBar(
            title: Text(book.Title ?? 'Unknown Title'),
            actions: [
              SizedBox(
                width: 200,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    final word = _searchController.text;
                    // TODO
                  },
                ),
              ),
            ],
          ),
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
