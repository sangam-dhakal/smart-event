import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();

  factory LocalDbService() => _instance;

  LocalDbService._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'smart_event.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE participants (
            guestId TEXT PRIMARY KEY,
            eventId TEXT,
            name TEXT,
            email TEXT,
            attendance INTEGER,
            sync_pending INTEGER
          )
        ''');
      },
    );
  }

  // Download event data for offline use
  Future<void> saveParticipantsOffline(
    List<Map<String, dynamic>> participants,
  ) async {
    final dbClient = await db;
    Batch batch = dbClient.batch();
    for (var p in participants) {
      batch.insert('participants', {
        'guestId': p['guestId'],
        'eventId': p['eventId'],
        'name': p['name'],
        'email': p['email'],
        'attendance': p['attendance'] == true ? 1 : 0,
        'sync_pending': 0, // 0 means it hasn't been scanned offline yet
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  // Mark attendance offline via Scanner
  Future<void> markAttendanceOffline(String guestId, String eventId) async {
    final dbClient = await db;

    final res = await dbClient.query(
      'participants',
      where: 'guestId = ? AND eventId = ?',
      whereArgs: [guestId, eventId],
    );

    if (res.isEmpty) {
      throw Exception(
        "Participant not found in offline DB. Did you download the event data?",
      );
    }
    if (res.first['attendance'] == 1) {
      throw Exception("Already checked in (Offline Database)");
    }

    await dbClient.update(
      'participants',
      {'attendance': 1, 'sync_pending': 1}, // Mark as attended and needing sync
      where: 'guestId = ?',
      whereArgs: [guestId],
    );
  }

  // Get scans that need to be uploaded to Firebase
  Future<List<Map<String, dynamic>>> getPendingSyncs(String eventId) async {
    final dbClient = await db;
    return await dbClient.query(
      'participants',
      where: 'eventId = ? AND sync_pending = 1',
      whereArgs: [eventId],
    );
  }

  // Clear the sync_pending flag after successful Firebase upload
  Future<void> markSynced(String guestId) async {
    final dbClient = await db;
    await dbClient.update(
      'participants',
      {'sync_pending': 0},
      where: 'guestId = ?',
      whereArgs: [guestId],
    );
  }
}
