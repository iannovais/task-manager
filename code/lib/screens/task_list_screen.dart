import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/sensor_service.dart';
import '../services/location_service.dart';
import '../services/camera_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../screens/task_form_screen.dart';
import '../widgets/task_card.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  List<Task> _tasks = [];
  String _filter = 'all';
  String _sortBy = 'date'; 
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = false;
  String _syncStatus = 'idle';
  bool _shouldShowSyncNotification = false;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _syncSubscription;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadTasks();
    _setupShakeDetection();
  }

  @override
  void dispose() {
    SensorService.instance.stop();
    _connectivitySubscription?.cancel();
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    await ConnectivityService.instance.initialize();
    
    await SyncService.instance.initialize();

    _connectivitySubscription = ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (mounted) {
        final wasOffline = !_isOnline;
        setState(() => _isOnline = isOnline);
        
        if (isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Conectado'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          
          if (wasOffline) {
            _shouldShowSyncNotification = true;
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Modo Offline'),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          _shouldShowSyncNotification = false;
        }
      }
    });

    _syncSubscription = SyncService.instance.onSyncEvent.listen((event) {
      if (mounted) {
        setState(() => _syncStatus = event);
        
        if (event == 'success' || event == 'error') {
          _loadTasks();
        }
        
        if (event == 'success' && _shouldShowSyncNotification) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Dados sincronizados'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          _shouldShowSyncNotification = false;
        } else if (event == 'error' && _shouldShowSyncNotification) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Erro na sincronização'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });

    setState(() {
      _isOnline = ConnectivityService.instance.isOnline;
    });
  }

  void _setupShakeDetection() {
    SensorService.instance.startShakeDetection(() {
      _showShakeDialog();
    });
  }

  void _showShakeDialog() {
    final pendingTasks = _tasks.where((t) => !t.completed).toList();
    
    if (pendingTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.celebration, color: Colors.white),
              SizedBox(width: 8),
              Text('Nenhuma tarefa pendente!'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.vibration, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('Shake detectado!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selecione uma tarefa para completar:'),
            const SizedBox(height: 16),
            ...pendingTasks.take(3).map((task) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => _completeTaskByShake(task),
              ),
            )),
            if (pendingTasks.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${pendingTasks.length - 3} outras',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeTaskByShake(Task task) async {
    try {
      final updated = task.copyWith(
        completed: true,
        completedAt: DateTime.now(),
        completedBy: 'shake',
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );

      await DatabaseService.instance.update(updated);
      
      SyncService.instance.queueOperation(
        taskId: updated.id!,
        operation: updated.serverId == null ? 'CREATE' : 'UPDATE',
      );
      
      Navigator.pop(context);
      
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = updated;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('"${task.title}" completa via shake!')),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    try {
      final tasks = await DatabaseService.instance.readAll();
      
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Task> get _filteredTasks {
    var filtered = _tasks;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((t) => 
        t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (t.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }

    switch (_filter) {
      case 'pending':
        filtered = filtered.where((t) => !t.completed).toList();
        break;
      case 'completed':
        filtered = filtered.where((t) => t.completed).toList();
        break;
      case 'with_photo':
        filtered = filtered.where((t) => t.hasPhoto).toList();
        break;
      case 'with_location':
        filtered = filtered.where((t) => t.hasLocation).toList();
        break;
      case 'high_priority':
        filtered = filtered.where((t) => t.priority == 'high').toList();
        break;
      default:
        break;
    }

    switch (_sortBy) {
      case 'priority':
        filtered.sort((a, b) {
          const priorityOrder = {'high': 0, 'medium': 1, 'low': 2};
          return (priorityOrder[a.priority] ?? 3).compareTo(priorityOrder[b.priority] ?? 3);
        });
        break;
      case 'title':
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'date':
      default:
        filtered.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
        break;
    }

    return filtered;
  }

  Map<String, int> get _statistics {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.completed).length;
    final pending = total - completed;
    final completionRate = total > 0 ? ((completed / total) * 100).round() : 0;
    
    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'completionRate': completionRate,
    };
  }

  Future<void> _testLWW() async {
    final tasksWithServerId = _tasks.where((t) => t.serverId != null).toList();
    
    if (tasksWithServerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Text('Crie uma tarefa online primeiro!'),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final task = tasksWithServerId.first;
    final db = await DatabaseService.instance.database;
    
    await db.rawUpdate('''
      UPDATE server_mirror 
      SET title = ?, updatedAt = ?
      WHERE serverId = ?
    ''', [
      '${task.title} [TESTE VENCEU]',
      DateTime.now().add(const Duration(minutes: 3)).toIso8601String(),
      task.serverId,
    ]);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.science, color: Colors.orange),
              SizedBox(width: 8),
              Text('Teste LWW Configurado'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tarefa: "${task.title}"', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Servidor simulado editou com timestamp futuro!'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Show paizão'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _filterByNearby() async {
    final position = await LocationService.instance.getCurrentLocation();
    
    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Não foi possível obter localização'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final nearbyTasks = await DatabaseService.instance.getTasksNearLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      radiusInMeters: 1000,
    );

    setState(() {
      _tasks = nearbyTasks;
      _filter = 'nearby';
      _searchQuery = '';
      _searchController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 8),
              Text('${nearbyTasks.length} tarefa(s) próxima(s)'),
            ],
          ),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja deletar "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (task.hasPhoto) {
          for (final p in task.photoPaths) {
            await CameraService.instance.deletePhoto(p);
          }
        }
        
        if (task.serverId != null) {
          await SyncService.instance.queueOperation(
            taskId: task.id!,
            operation: 'DELETE',
            payload: '{"serverId": "${task.serverId}"}',
          );
        }
        
        await DatabaseService.instance.delete(task.id!);
        await _loadTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.delete, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Tarefa deletada'),
                ],
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleComplete(Task task) async {
    try {
      final updated = task.copyWith(
        completed: !task.completed,
        completedAt: !task.completed ? DateTime.now() : null,
        completedBy: !task.completed ? 'manual' : null,
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );

      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = updated;
        }
      });

      await DatabaseService.instance.update(updated);
      
      SyncService.instance.queueOperation(
        taskId: updated.id!,
        operation: updated.serverId == null ? 'CREATE' : 'UPDATE',
      );
    } catch (e) {
      await _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _statistics;
    final filteredTasks = _filteredTasks;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Minhas Tarefas',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOnline ? Icons.cloud_done : Icons.cloud_off,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isOnline ? 'On' : 'Off',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar',
            onSelected: (value) {
              setState(() => _sortBy = value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _sortBy == 'date' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Data', style: TextStyle(color: _sortBy == 'date' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'priority',
                child: Row(
                  children: [
                    Icon(Icons.flag, color: _sortBy == 'priority' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Prioridade', style: TextStyle(color: _sortBy == 'priority' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'title',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, color: _sortBy == 'title' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Título', style: TextStyle(color: _sortBy == 'title' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            onSelected: (value) {
              if (value == 'lww_test') {
                _testLWW();
              } else {
                setState(() {
                  _filter = value;
                  _loadTasks();
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.list_alt, color: _filter == 'all' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Todas', style: TextStyle(color: _filter == 'all' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pending',
                child: Row(
                  children: [
                    Icon(Icons.pending_outlined, color: _filter == 'pending' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Pendentes', style: TextStyle(color: _filter == 'pending' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'completed',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: _filter == 'completed' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Concluídas', style: TextStyle(color: _filter == 'completed' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'high_priority',
                child: Row(
                  children: [
                    Icon(Icons.priority_high, color: _filter == 'high_priority' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Alta Prioridade', style: TextStyle(color: _filter == 'high_priority' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'with_photo',
                child: Row(
                  children: [
                    Icon(Icons.photo_camera, color: _filter == 'with_photo' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Com Foto', style: TextStyle(color: _filter == 'with_photo' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'with_location',
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: _filter == 'with_location' ? Colors.blue : Colors.black),
                    const SizedBox(width: 8),
                    Text('Com Localização', style: TextStyle(color: _filter == 'with_location' ? Colors.blue : Colors.black)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'lww_test',
                child: Row(
                  children: [
                    const Icon(Icons.science, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Testar LWW', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade700],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: 'Total',
                          value: stats['total'].toString(),
                          icon: Icons.list_alt,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        _StatItem(
                          label: 'Concluídas',
                          value: stats['completed'].toString(),
                          icon: Icons.check_circle,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        _StatItem(
                          label: 'Taxa',
                          value: '${stats['completionRate']}%',
                          icon: Icons.trending_up,
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar tarefas...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_filter != 'all' || _sortBy != 'date' || _searchQuery.isNotEmpty)
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (_filter != 'all')
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                avatar: Icon(_getFilterIcon(_filter), size: 16),
                                label: Text(_getFilterLabel(_filter)),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setState(() {
                                    _filter = 'all';
                                    _loadTasks();
                                  });
                                },
                              ),
                            ),
                          if (_sortBy != 'date')
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                avatar: const Icon(Icons.sort, size: 16),
                                label: Text('Ordenar: ${_getSortLabel(_sortBy)}'),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setState(() => _sortBy = 'date');
                                },
                              ),
                            ),
                          if (_searchQuery.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                avatar: const Icon(Icons.search, size: 16),
                                label: Text('"$_searchQuery"'),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: filteredTasks.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredTasks.length,
                            itemBuilder: (context, index) {
                              final task = filteredTasks[index];
                              return TaskCard(
                                task: task,
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TaskFormScreen(task: task),
                                    ),
                                  );
                                  if (result == true) _loadTasks();
                                },
                                onDelete: () => _deleteTask(task),
                                onCheckboxChanged: (value) => _toggleComplete(task),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TaskFormScreen(),
            ),
          );
          if (result == true) _loadTasks();
        },
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova Tarefa'),
      ),
    );
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case 'pending':
        return Icons.pending_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'high_priority':
        return Icons.priority_high;
      case 'with_photo':
        return Icons.photo_camera;
      case 'with_location':
        return Icons.location_on;
      case 'nearby':
        return Icons.near_me;
      default:
        return Icons.filter_list;
    }
  }

  String _getFilterLabel(String filter) {
    switch (filter) {
      case 'pending':
        return 'Pendentes';
      case 'completed':
        return 'Concluídas';
      case 'high_priority':
        return 'Alta Prioridade';
      case 'with_photo':
        return 'Com Foto';
      case 'with_location':
        return 'Com Localização';
      case 'nearby':
        return 'Próximas';
      default:
        return 'Todas';
    }
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'priority':
        return 'Prioridade';
      case 'title':
        return 'Título';
      case 'date':
      default:
        return 'Data';
    }
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_filter) {
      case 'pending':
        message = 'Nenhuma tarefa pendente!';
        icon = Icons.check_circle_outline;
        break;
      case 'completed':
        message = 'Nenhuma tarefa concluída ainda';
        icon = Icons.pending_outlined;
        break;
      case 'nearby':
        message = 'Nenhuma tarefa próxima';
        icon = Icons.near_me;
        break;
      default:
        message = 'Nenhuma tarefa ainda.\nToque em + para criar!';
        icon = Icons.add_task;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}