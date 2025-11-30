import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/task.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 8, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE tasks (
        id $idType,
        title $textType,
        description $textType,
        priority $textType,
        completed $intType,
        createdAt $textType,
        photoPaths TEXT,
        completedAt TEXT,
        completedBy TEXT,
        latitude REAL,
        longitude REAL,
        locationName TEXT,
        updatedAt $textType,
        syncStatus TEXT DEFAULT 'pending',
        serverId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id $idType,
        taskId INTEGER NOT NULL,
        operation $textType,
        timestamp $textType,
        payload TEXT,
        retryCount INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE server_mirror (
        serverId TEXT PRIMARY KEY,
        title $textType,
        description $textType,
        priority $textType,
        completed $intType,
        updatedAt $textType,
        syncedData TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tasks ADD COLUMN photoPath TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE tasks ADD COLUMN completedAt TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN completedBy TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE tasks ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN longitude REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN locationName TEXT');
    }

    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN photoPaths TEXT');

      final rows = await db.query('tasks', columns: ['id', 'photoPath']);
      for (final row in rows) {
        if (row['photoPath'] != null) {
          final id = row['id'] as int;
          final old = row['photoPath'] as String;
          final jsonStr = jsonEncode([old]);
          await db.update('tasks', {'photoPaths': jsonStr}, where: 'id = ?', whereArgs: [id]);
        }
      }
    }

    if (oldVersion < 6) {
      final columns = await db.rawQuery('PRAGMA table_info(tasks)');
      final columnNames = columns.map((col) => col['name'] as String).toSet();
      
      if (!columnNames.contains('updatedAt')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN updatedAt TEXT');
      }
      if (!columnNames.contains('syncStatus')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN syncStatus TEXT DEFAULT \'pending\'');
      }
      if (!columnNames.contains('serverId')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN serverId TEXT');
      }

      await db.execute('UPDATE tasks SET updatedAt = createdAt WHERE updatedAt IS NULL');

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            taskId INTEGER NOT NULL,
            operation TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            payload TEXT,
            retryCount INTEGER DEFAULT 0
          )
        ''');
      }
    }
    
    if (oldVersion < 7) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (tables.isNotEmpty) {
        final columns = await db.rawQuery('PRAGMA table_info(sync_queue)');
        final columnNames = columns.map((col) => col['name'] as String).toSet();
        
        if (!columnNames.contains('operation')) {
          await db.execute('DROP TABLE IF EXISTS sync_queue');
        }
      }
      
      final checkAgain = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (checkAgain.isEmpty) {
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            taskId INTEGER NOT NULL,
            operation TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            payload TEXT,
            retryCount INTEGER DEFAULT 0
          )
        ''');
      }
    }
    
    if (oldVersion < 8) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='server_mirror'"
      );
      
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE server_mirror (
            serverId TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            priority TEXT NOT NULL,
            completed INTEGER NOT NULL,
            updatedAt TEXT NOT NULL,
            syncedData TEXT
          )
        ''');
      }
    }
    
    debugPrint('[DB] Banco migrado de v$oldVersion para v$newVersion');
  }

  Future<Task> create(Task task) async {
    final db = await instance.database;
    final id = await db.insert('tasks', task.toMap());
    return task.copyWith(id: id);
  }

  Future<Task?> read(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Task.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Task>> readAll() async {
    final db = await instance.database;
    const orderBy = 'createdAt DESC';
    final result = await db.query('tasks', orderBy: orderBy);
    return result.map((json) => Task.fromMap(json)).toList();
  }

  Future<int> update(Task task) async {
    final db = await instance.database;
    return db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await instance.database;
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Task>> getTasksNearLocation({
    required double latitude,
    required double longitude,
    double radiusInMeters = 1000,
  }) async {
    final allTasks = await readAll();
    
    return allTasks.where((task) {
      if (!task.hasLocation) return false;
      
      final latDiff = (task.latitude! - latitude).abs();
      final lonDiff = (task.longitude! - longitude).abs();
      final distance = ((latDiff * 111000) + (lonDiff * 111000)) / 2;
      
      return distance <= radiusInMeters;
    }).toList();
  }

  Future<void> addToSyncQueue({
    required int taskId,
    required String operation, 
    String? payload,
  }) async {
    final db = await instance.database;
    await db.insert('sync_queue', {
      'taskId': taskId,
      'operation': operation,
      'timestamp': DateTime.now().toIso8601String(),
      'payload': payload,
      'retryCount': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await instance.database;
    return await db.query('sync_queue', orderBy: 'timestamp ASC');
  }

  Future<void> removeFromSyncQueue(int queueId) async {
    final db = await instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
  }

  Future<void> incrementSyncRetry(int queueId) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retryCount = retryCount + 1 WHERE id = ?',
      [queueId],
    );
  }

  Future<void> saveToServerMirror(Task task) async {
    if (task.serverId == null) return;
    
    final db = await instance.database;
    await db.insert(
      'server_mirror',
      {
        'serverId': task.serverId!,
        'title': task.title,
        'description': task.description ?? '',
        'priority': task.priority,
        'completed': task.completed ? 1 : 0,
        'updatedAt': task.updatedAt.toIso8601String(),
        'syncedData': jsonEncode(task.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Task?> fetchFromServerMirror(String serverId) async {
    final db = await instance.database;
    final maps = await db.query(
      'server_mirror',
      where: 'serverId = ?',
      whereArgs: [serverId],
    );

    if (maps.isEmpty) return null;

    final data = maps.first;
    return Task(
      serverId: data['serverId'] as String,
      title: data['title'] as String,
      description: data['description'] as String,
      priority: data['priority'] as String,
      completed: (data['completed'] as int) == 1,
      updatedAt: DateTime.parse(data['updatedAt'] as String),
      syncStatus: 'synced',
    );
  }

  Future<void> simulateServerEdit(String serverId, {
    required String newTitle,
    required DateTime serverTimestamp,
  }) async {
    final db = await instance.database;
    await db.update(
      'server_mirror',
      {
        'title': newTitle,
        'updatedAt': serverTimestamp.toIso8601String(),
      },
      where: 'serverId = ?',
      whereArgs: [serverId],
    );
    debugPrint('[DB] Simulado: Servidor editou tarefa $serverId com timestamp $serverTimestamp');
  }

  Future<void> incrementSyncRetry_OLD(int queueId) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retryCount = retryCount + 1 WHERE id = ?',
      [queueId],
    );
  }

  Future<void> clearSyncQueue() async {
    final db = await instance.database;
    await db.delete('sync_queue');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
