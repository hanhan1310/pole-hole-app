import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pole_hole_app/screen/permissions_screen.dart';
import 'package:pole_hole_app/screen/report_screen.dart';

import '../service/api_service.dart';
import 'main_screen.dart';

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pole Hole Detection'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        actions: [
          // Nút kiểm tra permissions
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: 'Quyền truy cập',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PermissionsScreen(),
                ),
              );
            },
          ),
          // Nút xem danh sách báo cáo
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Xem báo cáo',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReportScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              'Phát hiện ổ gà trên đường',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('Chụp ảnh để AI phân tích'),
            const SizedBox(height: 40),

            // Nút chụp ảnh
            ElevatedButton.icon(
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                // Chụp ảnh
                final XFile? image =
                await picker.pickImage(source: ImageSource.camera);

                if (image != null) {
                  // Gọi service xử lý
                  PotholeService service = PotholeService();
                  await service.processImage(image, context);
                }
              },
              icon: const Icon(Icons.camera),
              label: const Text("Chụp ảnh"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 10),

            // Nút chọn từ thư viện
            OutlinedButton.icon(
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                // Chọn từ thư viện
                final XFile? image =
                await picker.pickImage(source: ImageSource.gallery);

                if (image != null) {
                  // Gọi service xử lý
                  PotholeService service = PotholeService();
                  await service.processImage(image, context);
                }
              },
              icon: const Icon(Icons.photo_library),
              label: const Text("Chọn từ thư viện"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
