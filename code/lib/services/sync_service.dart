import 'dart:async';
import 'dart:convert';
import '../models/task.dart';
import 'database_service.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  final _syncController = StreamController<String>.broadcast();
  bool _isSyncing = false;
  Timer? _periodicSyncTimer;

  /// Stream de eventos de sincronização
  Stream<String> get onSyncEvent => _syncController.stream;

  /// Status da sincronização
  bool get isSyncing => _isSyncing;

  /// Inicializa o serviço de sincronização
  Future<void> initialize() async {
    // Monitora mudanças de conectividade
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        print('🔄 Conectividade restaurada - Iniciando sincronização...');
        sync();
      }
    });

    print('🔄 SyncService inicializado');
  }

  /// Executa a sincronização completa
  Future<void> sync() async {
    if (_isSyncing) {
      print('⚠️ Sincronização já em andamento, aguardando...');
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      print('📵 Offline - Sincronização adiada');
      _syncController.add('offline');
      return;
    }

    // Verificar se há algo na fila antes de começar
    final queueCheck = await DatabaseService.instance.getSyncQueue();
    if (queueCheck.isEmpty) {
      print('📭 Fila de sincronização vazia - nada a fazer');
      return;
    }

    _isSyncing = true;
    _syncController.add('syncing');

    try {
      print('🔄 Iniciando sincronização...');

      // Processar fila de sincronização (operações pendentes)
      await _processSyncQueue();

      _syncController.add('success');
      print('✅ Sincronização concluída com sucesso');
    } catch (e) {
      _syncController.add('error');
      print('❌ Erro na sincronização: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Processa a fila de sincronização (operações CREATE/UPDATE/DELETE)
  Future<void> _processSyncQueue() async {
    final queue = await DatabaseService.instance.getSyncQueue();

    if (queue.isEmpty) {
      print('📭 Fila de sincronização vazia');
      return;
    }

    print('📤 Processando ${queue.length} operação(ões) pendente(s)...');

    for (final item in queue) {
      try {
        final queueId = item['id'] as int;
        final taskId = item['taskId'] as int;
        final operation = item['operation'] as String;
        final retryCount = item['retryCount'] as int;

        // Limite de tentativas
        if (retryCount >= 3) {
          print('⚠️ Operação $operation para tarefa $taskId falhou após 3 tentativas');
          await DatabaseService.instance.removeFromSyncQueue(queueId);
          continue;
        }

        final task = await DatabaseService.instance.read(taskId);

        if (task == null && operation != 'DELETE') {
          // Tarefa foi deletada localmente, remover da fila
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
          print('✅ Operação $operation para tarefa $taskId sincronizada');
        } else {
          await DatabaseService.instance.incrementSyncRetry(queueId);
          print('⚠️ Falha na operação $operation para tarefa $taskId (tentativa ${retryCount + 1}/3)');
        }
      } catch (e) {
        print('❌ Erro ao processar item da fila: $e');
      }
    }
  }

  /// Sincroniza criação de tarefa
  Future<bool> _syncCreate(Task task) async {
    try {
      final serverTask = await ApiService.instance.createTask(task);
      
      // Atualizar tarefa local com serverId e status synced
      final updated = task.copyWith(
        serverId: serverTask.serverId,
        syncStatus: 'synced',
        updatedAt: DateTime.now(),
      );

      await DatabaseService.instance.update(updated);
      return true;
    } catch (e) {
      print('❌ Erro ao criar tarefa no servidor: $e');
      return false;
    }
  }

  /// Sincroniza atualização de tarefa
  Future<bool> _syncUpdate(Task task) async {
    try {
      if (task.serverId == null) {
        // Se não tem serverId, trata como CREATE
        return await _syncCreate(task);
      }

      // Buscar versão do servidor para resolver conflito (LWW)
      final serverTask = await ApiService.instance.fetchTask(task.serverId!);

      if (serverTask == null) {
        // Tarefa não existe no servidor, criar
        return await _syncCreate(task);
      }

      // RESOLUÇÃO DE CONFLITOS: Last-Write-Wins (LWW)
      if (serverTask.updatedAt.isAfter(task.updatedAt)) {
        // Servidor tem versão mais recente, sobrescrever local
        print('⚠️ Conflito detectado - Servidor mais recente, sobrescrevendo local');
        final merged = serverTask.copyWith(
          id: task.id,
          syncStatus: 'synced',
        );
        await DatabaseService.instance.update(merged);
        return true;
      } else {
        // Local mais recente, enviar para servidor
        print('✅ Local mais recente, enviando para servidor');
        await ApiService.instance.updateTask(task);
        
        final updated = task.copyWith(
          syncStatus: 'synced',
          updatedAt: DateTime.now(),
        );
        await DatabaseService.instance.update(updated);
        return true;
      }
    } catch (e) {
      print('❌ Erro ao atualizar tarefa no servidor: $e');
      return false;
    }
  }

  /// Sincroniza deleção de tarefa
  Future<bool> _syncDelete(String serverId) async {
    try {
      await ApiService.instance.deleteTask(serverId);
      return true;
    } catch (e) {
      print('❌ Erro ao deletar tarefa no servidor: $e');
      return false;
    }
  }

  /// Busca atualizações do servidor
  Future<void> _fetchServerUpdates() async {
    try {
      // Buscar todas as tarefas do servidor
      final serverTasks = await ApiService.instance.fetchTasks();
      final localTasks = await DatabaseService.instance.readAll();

      print('🔍 Verificando atualizações: ${serverTasks.length} no servidor, ${localTasks.length} locais');

      // Mapear tarefas locais por serverId
      final localMap = <String, Task>{};
      for (final task in localTasks) {
        if (task.serverId != null) {
          localMap[task.serverId!] = task;
        }
      }

      // Verificar tarefas do servidor
      for (final serverTask in serverTasks) {
        if (serverTask.serverId == null) continue;

        final localTask = localMap[serverTask.serverId!];

        if (localTask == null) {
          // Nova tarefa no servidor, adicionar localmente
          print('⬇️ Nova tarefa do servidor: ${serverTask.title}');
          await DatabaseService.instance.create(serverTask);
        } else if (serverTask.updatedAt.isAfter(localTask.updatedAt) && 
                   localTask.syncStatus == 'synced') {
          // Servidor tem versão mais recente e local está sincronizado
          print('⬇️ Atualizando tarefa local: ${serverTask.title}');
          final merged = serverTask.copyWith(
            id: localTask.id,
            syncStatus: 'synced',
          );
          await DatabaseService.instance.update(merged);
        }
      }
    } catch (e) {
      print('❌ Erro ao buscar atualizações do servidor: $e');
    }
  }

  /// Adiciona operação à fila
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

    print('📝 Operação $operation adicionada à fila para tarefa $taskId');

    // Só tentar sincronizar se online e não estiver já sincronizando
    if (ConnectivityService.instance.isOnline && !_isSyncing) {
      // Aguardar um pouco para agrupar operações
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isSyncing) {
          sync();
        }
      });
    }
  }

  /// Dispose
  void dispose() {
    _periodicSyncTimer?.cancel();
    _syncController.close();
  }
}
