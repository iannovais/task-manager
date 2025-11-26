import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_service.dart';

class GalleryService {
  static final GalleryService instance = GalleryService._init();
  GalleryService._init();

  final ImagePicker _picker = ImagePicker();

  Future<List<String>> pickMultipleAndSave(BuildContext context) async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 85);
      if (images == null || images.isEmpty) return [];

      final savedPaths = <String>[];
      for (final img in images) {
        final saved = await CameraService.instance.savePicture(img);
        savedPaths.add(saved);
      }

      return savedPaths;
    } catch (e) {
      print('Erro ao selecionar imagens da galeria: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar imagens: $e'), backgroundColor: Colors.red),
        );
      }
      return [];
    }
  }
}
