import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  ApiService._init();

  // CONFIGURAÇÃO DA API - Ajuste para seu servidor
  // Para testes locais, use o IP da sua máquina na rede local
  // Ex: 'http://192.168.1.100:3000' ou use um serviço mockado como JSONPlaceholder
  static const String baseUrl = 'https://jsonplaceholder.typicode.com/todos';
  
  // Headers padrão
  final Map<String, String> _headers = {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  /// Busca todas as tarefas do servidor
  Future<List<Task>> fetchTasks() async {
    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        // Como estamos usando JSONPlaceholder como exemplo, adaptamos os dados
        return jsonList.take(10).map((json) {
          return Task(
            serverId: json['id'].toString(),
            title: json['title'] ?? 'Sem título',
            description: 'Tarefa importada do servidor',
            priority: 'medium',
            completed: json['completed'] ?? false,
            syncStatus: 'synced',
          );
        }).toList();
      } else {
        throw Exception('Falha ao buscar tarefas: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisição: $e');
    }
  }

  /// Busca uma tarefa específica do servidor
  Future<Task?> fetchTask(String serverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$serverId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Task(
          serverId: json['id'].toString(),
          title: json['title'] ?? 'Sem título',
          description: 'Tarefa do servidor',
          priority: 'medium',
          completed: json['completed'] ?? false,
          syncStatus: 'synced',
        );
      } else if (response.statusCode == 404) {
        return null; // Tarefa não encontrada no servidor
      } else {
        throw Exception('Falha ao buscar tarefa: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisição: $e');
    }
  }

  /// Cria uma nova tarefa no servidor
  Future<Task> createTask(Task task) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: _headers,
        body: json.encode(task.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseJson = json.decode(response.body);
        
        // JSONPlaceholder retorna um ID mockado
        return task.copyWith(
          serverId: responseJson['id'].toString(),
          syncStatus: 'synced',
          updatedAt: DateTime.now(),
        );
      } else {
        throw Exception('Falha ao criar tarefa: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisição: $e');
    }
  }

  /// Atualiza uma tarefa no servidor
  Future<Task> updateTask(Task task) async {
    if (task.serverId == null) {
      throw Exception('Tarefa não possui serverId');
    }

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/${task.serverId}'),
        headers: _headers,
        body: json.encode(task.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return task.copyWith(
          syncStatus: 'synced',
          updatedAt: DateTime.now(),
        );
      } else {
        throw Exception('Falha ao atualizar tarefa: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisição: $e');
    }
  }

  /// Deleta uma tarefa no servidor
  Future<void> deleteTask(String serverId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/$serverId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Falha ao deletar tarefa: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisição: $e');
    }
  }

  /// Verifica a conectividade com o servidor
  Future<bool> checkServerConnection() async {
    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
