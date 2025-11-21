import 'dart:io';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/database_service.dart';
import '../services/camera_service.dart';
import '../services/gallery_service.dart';
import '../services/location_service.dart';
import '../widgets/location_picker.dart';

class TaskFormScreen extends StatefulWidget {
  final Task? task;

  const TaskFormScreen({super.key, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _priority = 'medium';
  bool _completed = false;
  bool _isLoading = false;
  
  // FOTOS (agora múltiplas)
  List<String> _photoPaths = [];
  
  // GPS
  double? _latitude;
  double? _longitude;
  String? _locationName;

  @override
  void initState() {
    super.initState();
    
    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description;
  _priority = widget.task!.priority;
  _completed = widget.task!.completed;
  _photoPaths = widget.task!.photoPaths;
  _latitude = widget.task!.latitude;
  _longitude = widget.task!.longitude;
  _locationName = widget.task!.locationName;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // CÂMERA METHODS
  Future<void> _takePicture() async {
    final photoPath = await CameraService.instance.takePicture(context);
    
    if (photoPath != null && mounted) {
      setState(() => _photoPaths.add(photoPath));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📷 Foto capturada!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    final saved = await GalleryService.instance.pickMultipleAndSave(context);
    if (saved.isNotEmpty && mounted) {
      setState(() => _photoPaths.addAll(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${saved.length} foto(s) adicionada(s)'), backgroundColor: Colors.green),
      );
    }
  }

  void _removePhotoAt(int index) async {
    final path = _photoPaths[index];
    final deleted = await CameraService.instance.deletePhoto(path);
    setState(() => _photoPaths.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? '🗑️ Foto removida' : '⚠️ Não foi possível remover a foto')),
    );
  }

  void _viewPhotoAt(int index) {
    final photoPath = _photoPaths[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(photoPath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  // GPS METHODS
  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: LocationPicker(
            initialLatitude: _latitude,
            initialLongitude: _longitude,
            initialAddress: _locationName,
            onLocationSelected: (lat, lon, address) {
              setState(() {
                _latitude = lat;
                _longitude = lon;
                _locationName = address;
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  void _removeLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _locationName = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📍 Localização removida')),
    );
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (widget.task == null) {
        // CRIAR
        final newTask = Task(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _priority,
          completed: _completed,
          photoPaths: _photoPaths,
          latitude: _latitude,
          longitude: _longitude,
          locationName: _locationName,
        );
        await DatabaseService.instance.create(newTask);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Tarefa criada'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // ATUALIZAR
        final updatedTask = widget.task!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _priority,
          completed: _completed,
          photoPaths: _photoPaths,
          latitude: _latitude,
          longitude: _longitude,
          locationName: _locationName,
        );
        await DatabaseService.instance.update(updatedTask);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Tarefa atualizada'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Tarefa' : 'Nova Tarefa'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TÍTULO
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título *',
                        hintText: 'Ex: Estudar Flutter',
                        prefixIcon: Icon(Icons.title),
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Digite um título';
                        }
                        if (value.trim().length < 3) {
                          return 'Mínimo 3 caracteres';
                        }
                        return null;
                      },
                      maxLength: 100,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // DESCRIÇÃO
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        hintText: 'Detalhes...',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // PRIORIDADE
                    DropdownButtonFormField<String>(
                      value: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Prioridade',
                        prefixIcon: Icon(Icons.flag),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('🟢 Baixa')),
                        DropdownMenuItem(value: 'medium', child: Text('🟡 Média')),
                        DropdownMenuItem(value: 'high', child: Text('🟠 Alta')),
                        DropdownMenuItem(value: 'urgent', child: Text('🔴 Urgente')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _priority = value);
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // SWITCH COMPLETA
                    SwitchListTile(
                      title: const Text('Tarefa Completa'),
                      subtitle: Text(_completed ? 'Sim' : 'Não'),
                      value: _completed,
                      onChanged: (value) => setState(() => _completed = value),
                      activeColor: Colors.green,
                      secondary: Icon(
                        _completed ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _completed ? Colors.green : Colors.grey,
                      ),
                    ),
                    
                    const Divider(height: 32),
                    
                    // SEÇÃO FOTO
                    Row(
                      children: [
                        const Icon(Icons.photo_camera, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Foto',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        // botões para câmera/galeria
                        OutlinedButton.icon(
                          onPressed: _takePicture,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Tirar Foto'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Galeria'),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),

                    if (_photoPaths.isNotEmpty)
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photoPaths.length,
                          itemBuilder: (context, index) {
                            final p = _photoPaths[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _viewPhotoAt(index),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(p),
                                        width: 200,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.transparent,
                                      child: IconButton(
                                        icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                                        onPressed: () => _removePhotoAt(index),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else
                      const SizedBox(),
                    
                    const Divider(height: 32),
                    
                    // SEÇÃO LOCALIZAÇÃO
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Localização',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_latitude != null)
                          TextButton.icon(
                            onPressed: _removeLocation,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remover'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    if (_latitude != null && _longitude != null)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.location_on, color: Colors.blue),
                          title: Text(_locationName ?? 'Localização salva'),
                          subtitle: Text(
                            LocationService.instance.formatCoordinates(
                              _latitude!,
                              _longitude!,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: _showLocationPicker,
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _showLocationPicker,
                        icon: const Icon(Icons.add_location),
                        label: const Text('Adicionar Localização'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    
                    const SizedBox(height: 32),
                    
                    // BOTÃO SALVAR
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveTask,
                      icon: const Icon(Icons.save),
                      label: Text(isEditing ? 'Atualizar' : 'Criar Tarefa'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}