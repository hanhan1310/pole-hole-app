import 'package:flutter/material.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text("Quyền ứng dụng"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.black),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildFancyPermissionTile("Máy ảnh", "Để chụp ảnh ổ gà", true, Icons.camera_alt),
          _buildFancyPermissionTile("Vị trí (GPS)", "Để xác định tọa độ đường", true, Icons.location_on),
          _buildFancyPermissionTile("Thư viện ảnh", "Để tải ảnh có sẵn", false, Icons.photo_library),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))]
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
                SizedBox(width: 15),
                Expanded(child: Text("Một số tính năng có thể không hoạt động nếu thiếu quyền.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFancyPermissionTile(String title, String subtitle, bool isGranted, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: isGranted ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: isGranted ? Colors.green : Colors.red),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Switch(
          value: isGranted,
          onChanged: (val){},
          activeColor: const Color(0xFF6C63FF),
        ),
      ),
    );
  }
}
