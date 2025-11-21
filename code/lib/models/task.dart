import 'dart:convert';

class Task {
  final int? id;
  final String title;
  final String description;
  final String priority;
  final bool completed;
  final DateTime createdAt;
  
  // Fotos (agora pode ter várias)
  final List<String> photoPaths;
  
  // SENSORES
  final DateTime? completedAt;
  final String? completedBy;      // 'manual', 'shake'
  
  // GPS
  final double? latitude;
  final double? longitude;
  final String? locationName;

  // OFFLINE-FIRST / SYNC
  final DateTime updatedAt;
  final String syncStatus;        // 'synced', 'pending', 'error'
  final String? serverId;         // ID retornado pelo servidor

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.priority,
    this.completed = false,
    DateTime? createdAt,
    List<String>? photoPaths,
    this.completedAt,
    this.completedBy,
    this.latitude,
    this.longitude,
    this.locationName,
    DateTime? updatedAt,
    this.syncStatus = 'pending',
    this.serverId,
  }) :
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now(),
    photoPaths = photoPaths ?? [];

  // Getters auxiliares
  bool get hasPhoto => photoPaths.isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;
  bool get wasCompletedByShake => completedBy == 'shake';
  bool get isSynced => syncStatus == 'synced';
  bool get isPending => syncStatus == 'pending';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'priority': priority,
      'completed': completed ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      // armazenamos a lista como JSON
      'photoPaths': photoPaths.isNotEmpty ? jsonEncode(photoPaths) : null,
      'completedAt': completedAt?.toIso8601String(),
      'completedBy': completedBy,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'serverId': serverId,
    };
  }

  // Serialização para API (sem campos internos)
  Map<String, dynamic> toJson() {
    return {
      if (serverId != null) 'id': serverId,
      'title': title,
      'description': description,
      'priority': priority,
      'completed': completed,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (completedBy != null) 'completedBy': completedBy,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationName != null) 'locationName': locationName,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    // Suporte retrocompatível: se existir `photoPaths` usamos ela,
    // se existir `photoPath` (antigo) migramos para lista com um elemento.
    List<String> parsedPhotoPaths = [];
    if (map['photoPaths'] != null) {
      try {
        final decoded = jsonDecode(map['photoPaths'] as String);
        if (decoded is List) {
          parsedPhotoPaths = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        // se decode falhar, ignoramos
      }
    } else if (map['photoPath'] != null) {
      parsedPhotoPaths = [map['photoPath'] as String];
    }

    return Task(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String,
      priority: map['priority'] as String,
      completed: (map['completed'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      photoPaths: parsedPhotoPaths,
      completedAt: map['completedAt'] != null 
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      completedBy: map['completedBy'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      locationName: map['locationName'] as String?,
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
      syncStatus: map['syncStatus'] as String? ?? 'pending',
      serverId: map['serverId'] as String?,
    );
  }

  // Deserialização da API
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      serverId: json['id']?.toString(),
      title: json['title'] as String,
      description: json['description'] as String,
      priority: json['priority'] as String,
      completed: json['completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      completedAt: json['completedAt'] != null 
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      completedBy: json['completedBy'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      locationName: json['locationName'] as String?,
      syncStatus: 'synced',
    );
  }

  Task copyWith({
    int? id,
    String? title,
    String? description,
    String? priority,
    bool? completed,
    DateTime? createdAt,
    List<String>? photoPaths,
    DateTime? completedAt,
    String? completedBy,
    double? latitude,
    double? longitude,
    String? locationName,
    DateTime? updatedAt,
    String? syncStatus,
    String? serverId,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      photoPaths: photoPaths ?? this.photoPaths,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      serverId: serverId ?? this.serverId,
    );
  }
}
