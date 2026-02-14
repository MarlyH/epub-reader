import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../constants.dart';

class LibraryDatabase {
  Database? _database;

  Future<Database> _getInstance() async {
    if (_database != null) return _database!;
    _database = await _init();
    return _database!;
  }

  Future<Database> _init() async {
    // For mobile platforms, sqflite uses the native implementation which is already set up.
    // For desktop platforms, we need to initialize the ffi implementation.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Create the db and the app directory if it doesn't exist
    final documentsDir = await getApplicationDocumentsDirectory();
    late Directory appDir;

    // Currently, on Windows we lazily create an app folder in Documents.
    // Later, we may move this to AppData and customise folder locations for each platform.
    if (Platform.isWindows) {
      appDir = Directory(join(documentsDir.path, appName));
      if (!await appDir.exists()) {
        await appDir.create();
      }
    } else {
      appDir = documentsDir;
    }
    final dbPath = join(appDir.path, 'library.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<bool> insertBook(String id, String title) async {
    final db = await _getInstance();
    try {
      await db.insert(
        'books',
        {
          'id': id,
          'title': title
        },
        conflictAlgorithm: ConflictAlgorithm.abort, // fail if already exists
      );
      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        // book already exists...
        return false;
      }
      rethrow;
    }
  }

  // db and version are provided by the openDatabase function when it calls onCreate
  Future<void> _createDatabase(Database db, int version) async {
    // id is a SHA-256 hash of EPUB file
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY, 
        title TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        word TEXT NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX idx_words_book_word
      ON words(book_id, word);
    ''');

    await db.execute('''
      CREATE TABLE occurrences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        cfi TEXT NOT NULL,
        FOREIGN KEY(word_id) REFERENCES words(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX idx_occurrences_word
      ON occurrences(word_id);
    ''');
  }
}