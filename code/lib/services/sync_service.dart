import 'dart:async';
import 'dart:convert';
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
        print('Conectividade restaurada - Iniciando sincronização...');
        sync();
      }
    });

    print('SyncService inicializado');
  }

  Future<void> sync() async {
    if (_isSyncing) {
      print('Sincronização já em andamento, aguardando...');
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      print('Offline - Sincronização adiada');
      _syncController.add('offline');
      return;
    }

    final queueCheck = await DatabaseService.instance.getSyncQueue();
    if (queueCheck.isEmpty) {
      print('Fila de sincronização vazia - nada a fazer');
      return;
    }

    _isSyncing = true;
    _syncController.add('syncing');

    try {
      print('Iniciando sincronização...');

      await _processSyncQueue();

      _syncController.add('success');
      print('Sincronização concluída com sucesso');
    } catch (e) {
      _syncController.add('error');
      print('Erro na sincronização: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _processSyncQueue() async {
    final queue = await DatabaseService.instance.getSyncQueue();

    if (queue.isEmpty) {
      print('Fila de sincronização vazia');
      return;
    }

    print('Processando ${queue.length} operação(ões) pendente(s)...');

    for (final item in queue) {
      try {
        final queueId = item['id'] as int;
        final taskId = item['taskId'] as int;
        final operation = item['operation'] as String;
        final retryCount = item['retryCount'] as int;

        if (retryCount >= 3) {
          print('Operação $operation para tarefa $taskId falhou após 3 tentativas');
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
          print('Operação $operation para tarefa $taskId sincronizada');
        } else {
          await DatabaseService.instance.incrementSyncRetry(queueId);
          print('Falha na operação $operation para tarefa $taskId (tentativa ${retryCount + 1}/3)');
        }
      } catch (e) {
        print('Erro ao processar item da fila: $e');
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
      
      print('CREATE: Tarefa ${updated.title} criada com serverId $serverId');
      return true;
    } catch (e) {
      print('Erro ao processar tarefa: $e');
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
        print('Tarefa não existe no servidor, criando...');
        return await _syncCreate(task);
      }

      print('LWW: Comparando timestamps...');
      print('   Local:    ${task.updatedAt} - "${task.title}"');
      print('   Servidor: ${serverTask.updatedAt} - "${serverTask.title}"');

      if (serverTask.updatedAt.isAfter(task.updatedAt)) {
        print('CONFLITO: Servidor mais recente! Sobrescrevendo local...');
        print('Mudando de "${task.title}" para "${serverTask.title}"');
        
        final merged = serverTask.copyWith(
          id: task.id,
          syncStatus: 'synced',
        );
        await DatabaseService.instance.update(merged);
        return true;
        
      } else {
        print('LOCAL mais recente! Enviando para servidor...');
        
        await DatabaseService.instance.saveToServerMirror(task);
        
        final updated = task.copyWith(
          syncStatus: 'synced',
        );
        await DatabaseService.instance.update(updated);
        return true;
      }
    } catch (e) {
      print('Erro ao processar atualização: $e');
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
