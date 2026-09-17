import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/time_entry.dart';
import '../models/timesheet_entry.dart';

/// Database locale (SQLite) usato esclusivamente come coda temporanea per
/// le timbrature e le righe ore effettuate offline, in attesa di
/// sincronizzazione con Business Central. Non è un'anagrafica: BC resta
/// l'unica fonte di verità (vedi specifica funzionale, sezione 3.2).
class LocalDbService {
  LocalDbService._internal();
  static final LocalDbService instance = LocalDbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'timbrature_offline.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createPunchesTable(db);
        await _createTimeEntriesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTimeEntriesTable(db);
        }
      },
    );
  }

  Future<void> _createPunchesTable(Database db) async {
    await db.execute('''
      CREATE TABLE pending_punches (
        local_id TEXT PRIMARY KEY,
        employee_id TEXT,
        project_id TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        status TEXT NOT NULL,
        error_message TEXT
      )
    ''');
  }

  Future<void> _createTimeEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE pending_time_entries (
        local_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        task_id TEXT,
        date TEXT NOT NULL,
        hours REAL NOT NULL,
        note TEXT,
        status TEXT NOT NULL,
        error_message TEXT
      )
    ''');
  }

  // --- Timbrature ---

  Future<void> savePunch(TimesheetPunch punch) async {
    final db = await database;
    await db.insert(
      'pending_punches',
      punch.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TimesheetPunch>> getPendingPunches() async {
    final db = await database;
    final rows = await db.query(
      'pending_punches',
      where: 'status = ?',
      whereArgs: [SyncStatus.pending.name],
      orderBy: 'timestamp ASC',
    );
    return rows.map(TimesheetPunch.fromDbMap).toList();
  }

  /// Tutte le timbrature registrate in locale per una data specifica
  /// (indipendentemente dal loro stato di sincronizzazione): serve per
  /// calcolare le ore lavorate della giornata anche prima che le
  /// timbrature siano state confermate da Business Central.
  Future<List<TimesheetPunch>> getPunchesForDate(DateTime date) async {
    final db = await database;
    final prefix = _dateOnly(date);
    final rows = await db.query(
      'pending_punches',
      where: 'timestamp LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'timestamp ASC',
    );
    return rows.map(TimesheetPunch.fromDbMap).toList();
  }

  Future<List<TimesheetPunch>> getTodayPunches() => getPunchesForDate(DateTime.now());

  Future<void> markSynced(String localId) async {
    final db = await database;
    await db.update(
      'pending_punches',
      {'status': SyncStatus.synced.name, 'error_message': null},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markFailed(String localId, String errorMessage) async {
    final db = await database;
    await db.update(
      'pending_punches',
      {'status': SyncStatus.failed.name, 'error_message': errorMessage},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  // --- Righe ore su progetti/task ---

  Future<void> saveTimeEntry(TimeEntry entry) async {
    final db = await database;
    await db.insert(
      'pending_time_entries',
      entry.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTimeEntry(String localId) async {
    final db = await database;
    await db.delete(
      'pending_time_entries',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<TimeEntry>> getPendingTimeEntries() async {
    final db = await database;
    final rows = await db.query(
      'pending_time_entries',
      where: 'status = ?',
      whereArgs: [SyncStatus.pending.name],
    );
    return rows.map(TimeEntry.fromDbMap).toList();
  }

  /// Tutte le righe ore inserite (in qualunque stato) per una data
  /// specifica, usate per mostrare all'utente cosa ha già ripartito oggi.
  Future<List<TimeEntry>> getTimeEntriesForDate(DateTime date) async {
    final db = await database;
    final rows = await db.query(
      'pending_time_entries',
      where: 'date = ?',
      whereArgs: [_dateOnly(date)],
    );
    return rows.map(TimeEntry.fromDbMap).toList();
  }

  Future<void> markTimeEntrySynced(String localId) async {
    final db = await database;
    await db.update(
      'pending_time_entries',
      {'status': SyncStatus.synced.name, 'error_message': null},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markTimeEntryFailed(String localId, String errorMessage) async {
    final db = await database;
    await db.update(
      'pending_time_entries',
      {'status': SyncStatus.failed.name, 'error_message': errorMessage},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);
}

