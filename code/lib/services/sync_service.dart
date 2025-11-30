import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/task.dart';
import 'database_service.dart';
import 'connectivity_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  final _syncController = StreamController<String>.broadcast();
  bool _isSyncing = false;
  Timer? _periodicSyncTimer;

  Stream<String> get onSyncEvent => _syncController.stream;

  bool get isSyncing => _isSyncing;

  Future<void> initialize() async {
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        debugPrint('[SYNC] Conectividade restaurada - Iniciando sincronização...');
        sync();
      }
    });

    debugPrint('[SYNC] SyncService inicializado');
  }

  Future<void> sync() async {
    if (_isSyncing) {
      debugPrint('[SYNC] Sincronização já em andamento, aguardando...');
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      debugPrint('[SYNC] Offline - Sincronização adiada');
      _syncController.add('offline');
      return;
    }

    final queueCheck = await DatabaseService.instance.getSyncQueue();
    if (queueCheck.isEmpty) {
      // Fila vazia
      return;
    }

    _isSyncing = true;
    _syncController.add('syncing');

    try {
      debugPrint('[SYNC] Iniciando sincronização...');

      await _processSyncQueue();

      _syncController.add('success');
      debugPrint('[SYNC] Sincronização concluída com sucesso');
    } catch (e) {
      _syncController.add('error');
      debugPrint('[SYNC] Erro na sincronização: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processSyncQueue() async {
    final queue = await DatabaseService.instance.getSyncQueue();

    if (queue.isEmpty) {
      return;
    }

    debugPrint('[SYNC] Processando ${queue.length} operação(ões) pendente(s)...');

    for (final item in queue) {
      try {
        final queueId = item['id'] as int;
        final taskId = item['taskId'] as int;
        final operation = item['operation'] as String;
        final retryCount = item['retryCount'] as int;

        if (retryCount >= 3) {
          // Falhou após 3 tentativas
          await DatabaseService.instance.removeFromSyncQueue(queueId);
          continue;
        }

        final task = await DatabaseService.instance.read(taskId);

        if (task == null && operation != 'DELETE') {
          await DatabaseService.instance.removeFromSyncQueue(queueId);
          continue;
        }

        bool success = false;

        switch (operation) {
          case 'CREATE':
            success = await _syncCreate(task!);
            break;
          case 'UPDATE':
            success = await _syncUpdate(task!);
            break;
          case 'DELETE':
            final payload = item['payload'] as String?;
            if (payload != null) {
              final data = jsonDecode(payload);
              final serverId = data['serverId'] as String?;
              if (serverId != null) {
                success = await _syncDelete(serverId);
              }
            }
            break;
        }

        if (success) {
          await DatabaseService.instance.removeFromSyncQueue(queueId);
          debugPrint('[SYNC] Operação $operation para tarefa $taskId sincronizada');
        } else {
          await DatabaseService.instance.incrementSyncRetry(queueId);
        }
      } catch (e) {
        // Erro ao processar item
      }
    }
  }

  Future<bool> _syncCreate(Task task) async {
    try {
      final serverId = DateTime.now().millisecondsSinceEpoch.toString();
      
      final updated = task.copyWith(
        serverId: serverId,
        syncStatus: 'synced',
      );

      await DatabaseService.instance.saveToServerMirror(updated);
      
      await DatabaseService.instance.update(updated);
      
      debugPrint('[SYNC] CREATE: Tarefa ${updated.title} criada com serverId $serverId');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _syncUpdate(Task task) async {
    try {
      if (task.serverId == null) {
        return await _syncCreate(task);
      }

      final serverTask = await DatabaseService.instance.fetchFromServerMirror(task.serverId!);

      if (serverTask == null) {
        return await _syncCreate(task);
      }

      debugPrint('   [LWW] Comparando timestamps...');
      debugPrint('   [LWW] Local:    ${task.updatedAt} - "${task.title}"');
      debugPrint('   [LWW] Servidor: ${serverTask.updatedAt} - "${serverTask.title}"');

      if (serverTask.updatedAt.isAfter(task.updatedAt)) {
        debugPrint('   [LWW] CONFLITO: Servidor mais recente! Sobrescrevendo local...');
        debugPrint('   [LWW] Mudando de "${task.title}" para "${serverTask.title}"');
        
        final merged = serverTask.copyWith(
          id: task.id,
          syncStatus: 'synced',
        );
        await DatabaseService.instance.update(merged);
        return true;
        
      } else {
        debugPrint('[LWW] LOCAL mais recente! Enviando para servidor...');
        
        await DatabaseService.instance.saveToServerMirror(task);
        
        final updated = task.copyWith(
          syncStatus: 'synced',
        );
        await DatabaseService.instance.update(updated);
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> _syncDelete(String serverId) async {
    try {
      final db = await DatabaseService.instance.database;
      await db.delete('server_mirror', where: 'serverId = ?', whereArgs: [serverId]);
      print('DELETE: Tarefa removida do servidor (serverId: $serverId)');
      return true;
    } catch (e) {
      print('Erro ao processar deleção: $e');
      return false;
    }
  }

  Future<void> queueOperation({
    required int taskId,
    required String operation,
    String? payload,
  }) async {
    await DatabaseService.instance.addToSyncQueue(
      taskId: taskId,
      operation: operation,
      payload: payload,
    );

    print('Operação $operation adicionada à fila para tarefa $taskId');

    if (ConnectivityService.instance.isOnline && !_isSyncing) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isSyncing) {
          sync();
        }
      });
    }
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _syncController.close();
  }
}
