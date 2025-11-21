import 'dart:async';
import 'dart:convert';
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
      version: 7,  // bump para corrigir sync_queue
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    // Tabela de tarefas
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

    // Tabela de fila de sincronização
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
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migração incremental para cada versão
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
    // v5: adiciona coluna photoPaths (JSON lista) e migra valores de photoPath existentes
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN photoPaths TEXT');

      // migrar valores antigos de photoPath para photoPaths (JSON array)
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
    // v6: adiciona suporte offline-first (updatedAt, syncStatus, serverId, sync_queue)
    if (oldVersion < 6) {
      // Verificar se as colunas já existem antes de adicionar
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

      // Preencher updatedAt com createdAt para tarefas existentes
      await db.execute('UPDATE tasks SET updatedAt = createdAt WHERE updatedAt IS NULL');

      // Verificar se tabela sync_queue já existe
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (tables.isEmpty) {
        // Criar tabela sync_queue
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
    
    // v7: Garantir que sync_queue existe e está correta
    if (oldVersion < 7) {
      // Recriar sync_queue se necessário
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (tables.isNotEmpty) {
        // Verificar se tem todas as colunas necessárias
        final columns = await db.rawQuery('PRAGMA table_info(sync_queue)');
        final columnNames = columns.map((col) => col['name'] as String).toSet();
        
        if (!columnNames.contains('operation')) {
          // Recriar tabela
          await db.execute('DROP TABLE IF EXISTS sync_queue');
        }
      }
      
      // Criar tabela sync_queue se não existir ou foi deletada
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
    print('✅ Banco migrado de v$oldVersion para v$newVersion');
  }

  // CRUD Methods
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

  // Método especial: buscar tarefas por proximidade
  Future<List<Task>> getTasksNearLocation({
    required double latitude,
    required double longitude,
    double radiusInMeters = 1000,
  }) async {
    final allTasks = await readAll();
    
    return allTasks.where((task) {
      if (!task.hasLocation) return false;
      
      // Cálculo de distância usando fórmula de Haversine (simplificada)
      final latDiff = (task.latitude! - latitude).abs();
      final lonDiff = (task.longitude! - longitude).abs();
      final distance = ((latDiff * 111000) + (lonDiff * 111000)) / 2;
      
      return distance <= radiusInMeters;
    }).toList();
  }

  // =================== SYNC QUEUE METHODS ===================
  
  /// Adiciona uma operação à fila de sincronização
  Future<void> addToSyncQueue({
    required int taskId,
    required String operation, // 'CREATE', 'UPDATE', 'DELETE'
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

  /// Obtém todos os itens pendentes na fila de sincronização
  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await instance.database;
    return await db.query('sync_queue', orderBy: 'timestamp ASC');
  }

  /// Remove um item da fila de sincronização
  Future<void> removeFromSyncQueue(int queueId) async {
    final db = await instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
  }

  /// Incrementa o contador de tentativas de um item na fila
  Future<void> incrementSyncRetry(int queueId) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retryCount = retryCount + 1 WHERE id = ?',
      [queueId],
    );
  }

  /// Limpa toda a fila de sincronização
  Future<void> clearSyncQueue() async {
    final db = await instance.database;
    await db.delete('sync_queue');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}