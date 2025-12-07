import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

/// =============================================================================
/// Màn hình kiểm tra và yêu cầu các quyền cần thiết
/// =============================================================================
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  Map<String, PermissionStatus> _permissions = {};
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
  }

  /// Kiểm tra tất cả quyền
  Future<void> _checkAllPermissions() async {
    setState(() => _isChecking = true);

    try {
      // Kiểm tra từng permission
      // Android 13+ cần dùng Permission.photos thay vì .storage
      _permissions = {
        'Camera': await Permission.camera.status,
        'Photos': await Permission.photos.status, // Android 13+ (READ_MEDIA_IMAGES)
        'Location': await Permission.location.status,
      };
      
      // Log để debug
      print("📋 Permission Status:");
      _permissions.forEach((key, value) {
        print("   $key: ${value.toString()}");
      });
    } catch (e) {
      print("Lỗi check permissions: $e");
    }

    setState(() => _isChecking = false);
  }

  /// Yêu cầu một permission cụ thể
  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    
    setState(() {
      _permissions[name] = status;
    });

    if (status.isPermanentlyDenied) {
      // Nếu người dùng chọn "Don't ask again"
      _showOpenSettingsDialog(name);
    }
  }

  /// Hiển thị dialog mở Settings
  void _showOpenSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cần cấp quyền'),
        content: Text(
          'Quyền $permissionName bị từ chối vĩnh viễn.\n\n'
          'Vui lòng vào Settings để bật quyền này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(ctx);
            },
            child: const Text('Mở Settings'),
          ),
        ],
      ),
    );
  }

  /// Test GPS
  Future<void> _testGPS() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      Navigator.pop(context); // Đóng loading

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ GPS hoạt động'),
          content: Text(
            'Vị trí hiện tại:\n\n'
            'Latitude: ${position.latitude}\n'
            'Longitude: ${position.longitude}\n'
            'Accuracy: ${position.accuracy}m',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Đóng loading
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('❌ Lỗi GPS'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quyền truy cập'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAllPermissions,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                const Card(
                  color: Colors.blue,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(Icons.security, color: Colors.white, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'Quyền cần thiết',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'App cần các quyền sau để hoạt động',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Camera Permission
                _buildPermissionCard(
                  icon: Icons.camera_alt,
                  title: 'Camera',
                  description: 'Chụp ảnh đường xá để phát hiện ổ gà',
                  status: _permissions['Camera'],
                  onRequest: () => _requestPermission(
                    'Camera',
                    Permission.camera,
                  ),
                ),

                // Photos Permission (Android 13+)
                _buildPermissionCard(
                  icon: Icons.photo_library,
                  title: 'Thư viện ảnh',
                  description: 'Chọn ảnh từ thư viện để phân tích (Android 13+: READ_MEDIA_IMAGES)',
                  status: _permissions['Photos'],
                  onRequest: () => _requestPermission(
                    'Photos',
                    Permission.photos,
                  ),
                ),

                // Location Permission
                _buildPermissionCard(
                  icon: Icons.location_on,
                  title: 'Vị trí GPS',
                  description: 'Lưu tọa độ nơi phát hiện ổ gà',
                  status: _permissions['Location'],
                  onRequest: () => _requestPermission(
                    'Location',
                    Permission.location,
                  ),
                ),

                const SizedBox(height: 24),

                // Test GPS button
                ElevatedButton.icon(
                  onPressed: _testGPS,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Test GPS'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),

                const SizedBox(height: 16),

                // Hướng dẫn
                Card(
                  color: Colors.orange[50],
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'Lưu ý',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• App sẽ tự động yêu cầu quyền khi cần\n'
                          '• Bạn có thể từ chối, nhưng một số tính năng sẽ bị hạn chế\n'
                          '• GPS có thể dùng tọa độ mặc định nếu không có quyền',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required PermissionStatus? status,
    required VoidCallback onRequest,
  }) {
    final isGranted = status?.isGranted ?? false;
    final isDenied = status?.isDenied ?? false;
    final isPermanentlyDenied = status?.isPermanentlyDenied ?? false;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isGranted) {
      statusColor = Colors.green;
      statusText = 'Đã cấp';
      statusIcon = Icons.check_circle;
    } else if (isPermanentlyDenied) {
      statusColor = Colors.red;
      statusText = 'Bị từ chối';
      statusIcon = Icons.block;
    } else if (isDenied) {
      statusColor = Colors.orange;
      statusText = 'Chưa cấp';
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.grey;
      statusText = 'Chưa kiểm tra';
      statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 40, color: Colors.blue),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: isGranted
            ? null
            : ElevatedButton(
                onPressed: onRequest,
                child: Text(isPermanentlyDenied ? 'Settings' : 'Cấp quyền'),
              ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

