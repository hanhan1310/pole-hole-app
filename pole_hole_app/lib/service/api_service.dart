import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_service.dart';

class PotholeService {
  final Dio _dio = Dio();

  final FirebaseService _firebaseService = FirebaseService();

  // URL của AI Server (Thay IP theo máy của bạn)
  // - Emulator Android: 10.0.2.2
  // - Thiết bị thật: 192.168.x.x (chạy ipconfig để xem)
  final String _apiUrl = "http://192.168.0.117:8000/predict";

  Future<dynamic> processImage(XFile imageFile, BuildContext context) async {
    try {
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(imageFile.path,
            filename: "upload.jpg"),
      });

      var response = await _dio.post(_apiUrl, data: formData);

      if (response.statusCode == 200 && response.data['success'] == true) {

        var data = response.data;


        String status = data['status']; // "red", "yellow", "green"
        int potholeCount = data['pothole_count'] ?? 0; // Số lượng ổ gà
        String base64Image = data['image_base64']; // Ảnh đã vẽ (base64)
        Uint8List imageBytes = base64Decode(base64Image);

        Map<String, dynamic> dataReturn = {
          'status': status,
          'potholeCount': potholeCount,
          'imageBytes': imageBytes,
        };


        return dataReturn;
      } else {
        throw Exception("AI Server trả về lỗi: ${response.data}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Lỗi: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return null;
    }
  }

  Future<void> saveToFirebase(
    Uint8List imageBytes,
    String status,
    int potholeCount,
    BuildContext context,
  ) async {
    try {
      double lat = 21.0285; // Default: Hà Nội
      double lng = 105.8542;

      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (e) {
        log("Lỗi get current position: $e");
      }

      String fileName = "pothole_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(imageBytes);

      final ref =
          FirebaseStorage.instance.ref().child('pothole_images/$fileName');
      await ref.putFile(tempFile);
      String imageUrl = await ref.getDownloadURL(); // Lấy URL dạng String

      await tempFile.delete();

      if (imageUrl == null) {
        throw Exception("Upload ảnh thất bại");
      }

      await _firebaseService.saveReport(
        imageUrl: imageUrl, 
        status: status, 
        lat: lat, 
        lng: lng, 
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đã lưu báo cáo ($potholeCount ổ gà)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      // Hiển thị thông báo lỗi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Lỗi lưu Firebase: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

}


String getStatusText(String status) {
  switch (status) {
    case 'red':
      return '⚠️ NGHIÊM TRỌNG - Cần sửa chữa ngay';
    case 'yellow':
      return '⚡ CẢNH BÁO - Cần theo dõi';
    case 'green':
      return '✅ TỐT - Đường ổn định';
    default:
      return 'Không xác định';
  }
}

Color getStatusColor(String status) {
  switch (status) {
    case 'red':
      return Colors.red;
    case 'yellow':
      return Colors.orange;
    case 'green':
      return Colors.green;
    default:
      return Colors.grey;
  }
}
