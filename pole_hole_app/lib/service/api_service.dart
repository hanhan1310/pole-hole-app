import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_service.dart';

class PotholeService {
  late final Dio _dio;

  final FirebaseService _firebaseService = FirebaseService();

  // URL của AI Server (Thay IP theo máy của bạn)
  // - Emulator Android: 10.0.2.2
  // - Thiết bị thật: 192.168.x.x (chạy ipconfig để xem)

  ///wifi aibat
  // final String _apiUrl = "http://192.168.0.117:8000/predict";

  ///home wifi
  // final String _apiUrl = "http://192.168.1.61:8000/predict";

  ///ngrok api
  final String _apiUrl = "https://dominque-uninserted-dogmatically.ngrok-free.dev/predict";
  PotholeService() {
    // Cấu hình Dio với timeout
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        "ngrok-skip-browser-warning": "true",
      },
    ));
  }

  final String _cloudName = "dwsslesdj";
  final String _uploadPreset = "polehoie";

  Future<String?> uploadImageToCloudinary(File imageFile) async {
    try {
      // URL upload của Cloudinary
      String url = "https://api.cloudinary.com/v1_1/$_cloudName/image/upload";

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(imageFile.path),
        "upload_preset": _uploadPreset,
      });

      Response response = await _dio.post(url, data: formData);

      if (response.statusCode == 200) {
        String uploadedUrl = response.data["secure_url"];
        return uploadedUrl;
      }
    } catch (e) {
      print("❌ Lỗi upload Cloudinary: $e");
    }
    return null;
  }

  Future<dynamic> processImage(XFile imageFile, BuildContext context) async {
    try {
      // Đọc file ảnh
      final file = File(imageFile.path);
      final fileSize = await file.length();
      final sizeMB = fileSize / 1024 / 1024;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          imageFile.path,
          filename: "upload.jpg",
        ),
      });

      final stopwatch = Stopwatch()..start();

      var response = await _dio.post(
        _apiUrl,
        data: formData,
        onSendProgress: (sent, total) {
          if (total != -1) {
            final progress = (sent / total * 100).toStringAsFixed(1);
          }
        },
        onReceiveProgress: (received, total) {
          final elapsed = stopwatch.elapsedMilliseconds / 1000;
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(1);
            print("   📥 Download: $progress% - ${elapsed.toStringAsFixed(1)}s");
          } else {
            print("   📥 Received: $received bytes - ${elapsed.toStringAsFixed(1)}s");
          }
        },
      );

      stopwatch.stop();

      if (response.statusCode == 200 && response.data['success'] == true) {
        var data = response.data;

        log(response.toString());
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
      String errorMessage = "Lỗi không xác định";
      log(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return null;
    }
  }

  Future<void> saveToFirebase(
    Uint8List imageBytes, // Ảnh kết quả từ AI (dạng bytes)
    String status,
    int potholeCount,
    String addressStart,
    String addressEnd,
    double startLat,
    double startLng,
    double endLat,
    double endLng,
    String dateReport,
    String note,
    double lat,
    double lng,
    BuildContext context,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      String fileName = "pothole_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(imageBytes);

      String? imageUrl = await uploadImageToCloudinary(tempFile);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (imageUrl == null) {
        throw Exception("Không thể upload ảnh lên Cloudinary. Kiểm tra mạng hoặc Preset.");
      }

      await _firebaseService.saveReport(
        imageUrl: imageUrl, // Link từ Cloudinary
        status: status,
        lat: lat,
        lng: lng,
        addressStart: addressStart,
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
        addressEnd: addressEnd,
        dateReport: dateReport,
        note: note,
        potholeCount: potholeCount,
      );

      // BƯỚC 4: Thông báo thành công
      if (context.mounted) {
        Navigator.pop(context); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã gửi báo cáo thành công!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Tắt loading nếu lỗi
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
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
