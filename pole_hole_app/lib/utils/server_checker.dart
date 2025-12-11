import 'package:dio/dio.dart';

/// Utility để check server AI có sống không
class ServerChecker {
  static Future<Map<String, dynamic>> checkServer(String apiUrl) async {
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    print("🔍 KIỂM TRA KẾT NỐI SERVER AI");
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
    
    // Extract base URL (bỏ /predict)
    final baseUrl = apiUrl.replaceAll('/predict', '');
    
    try {
      print("📍 URL: $baseUrl");
      print("⏰ Timeout: 5s");
      print("⏳ Đang kết nối...\n");
      
      final stopwatch = Stopwatch()..start();
      
      // Try GET root endpoint
      final response = await dio.get(baseUrl);
      
      stopwatch.stop();
      
      print("✅ KẾT NỐI THÀNH CÔNG!");
      print("   ⚡ Thời gian: ${stopwatch.elapsedMilliseconds}ms");
      print("   📊 Status: ${response.statusCode}");
      
      if (response.statusCode == 200) {
        print("   🎉 Server đang hoạt động tốt!");
      } else if (response.statusCode == 404) {
        print("   ⚠️  Endpoint / không tồn tại (bình thường với FastAPI)");
        print("   💡 Nhưng server vẫn đang chạy!");
      }
      
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
      
      return {
        'success': true,
        'time': stopwatch.elapsedMilliseconds,
        'status': response.statusCode,
      };
      
    } on DioException catch (e) {
      print("❌ LỖI KẾT NỐI:");
      
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          print("   ⏰ Timeout - Server không phản hồi trong 5s");
          print("\n💡 NGUYÊN NHÂN CÓ THỂ:");
          print("   1. Server chưa chạy");
          print("   2. IP sai");
          print("   3. Firewall chặn");
          break;
          
        case DioExceptionType.connectionError:
          print("   🔌 Không kết nối được");
          print("\n💡 NGUYÊN NHÂN CÓ THỂ:");
          print("   1. Server chưa chạy");
          print("   2. IP sai: $baseUrl");
          print("   3. Không cùng WiFi");
          print("   4. Port 8000 bị chặn");
          break;
          
        case DioExceptionType.badResponse:
          // 404 là OK (FastAPI không có root endpoint)
          if (e.response?.statusCode == 404) {
            print("   📝 404 Not Found (bình thường)");
            print("   ✅ Server đang chạy!");
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
            return {
              'success': true,
              'status': 404,
              'message': 'Server running (404 is OK for FastAPI)',
            };
          }
          print("   🚫 Server trả về: ${e.response?.statusCode}");
          break;
          
        default:
          print("   ❓ Lỗi: ${e.message}");
      }
      
      print("\n🔧 CÁCH SỬA:");
      print("   1. Mở terminal:");
      print("      cd D:\\DAI_HOC\\datn_tttn\\pole_hole\\polehole_server");
      print("   2. Chạy:");
      print("      python main.py");
      print("   3. Hoặc:");
      print("      uvicorn main:app --reload --host 0.0.0.0 --port 8000");
      print("   4. Kiểm tra IP:");
      print("      ipconfig (Windows) / ifconfig (Mac/Linux)");
      
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
      
      return {
        'success': false,
        'error': e.type.toString(),
        'message': e.message,
      };
    } catch (e) {
      print("❌ LỖI KHÔNG XÁC ĐỊNH: $e");
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
      
      return {
        'success': false,
        'error': 'unknown',
        'message': e.toString(),
      };
    }
  }
  
  /// Check nhanh
  static Future<bool> isServerAlive(String apiUrl) async {
    final result = await checkServer(apiUrl);
    return result['success'] == true;
  }
}

