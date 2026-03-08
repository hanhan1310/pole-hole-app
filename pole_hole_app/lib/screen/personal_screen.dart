import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'manage_surveysor_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  Map<String, PermissionStatus> _permissions = {};
  bool _isLoading = false;
  bool _isAdmin = false;
  String? userName;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkRole();
    _loadDataFromFirestore();
  }

  Future<void> _checkRole() async {
    if (_user == null) return;
    try {
      var doc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      if (doc.exists && doc.get('role') == 'admin') {
        if (mounted) setState(() => _isAdmin = true);
      }
    } catch (e) {
      log("Error check role: $e");
    }
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final locationStatus = await Permission.location.status;
    PermissionStatus photoStatus;

    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          photoStatus = await Permission.photos.status;
        } else {
          photoStatus = await Permission.storage.status;
        }
      } catch (e) {
        photoStatus = await Permission.storage.status;
      }
    } else {
      photoStatus = await Permission.photos.status;
    }

    if (mounted) {
      setState(() {
        _permissions = {
          'Camera': cameraStatus,
          'Thư viện ảnh': photoStatus,
          'Vị trí (GPS)': locationStatus,
        };
      });
    }
  }

  Future<void> _requestPhotoPermission() async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        status = await Permission.photos.request();
      } else {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.photos.request();
    }
    _checkPermissions();
  }

  Future<void> _requestSpecificPermission(Permission permission) async {
    final status = await permission.request();
    _checkPermissions();
    if (status.isPermanentlyDenied) {
      if (mounted) _showOpenSettingsDialog();
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấp quyền trong Cài đặt'),
        content: const Text('Quyền này đã bị từ chối vĩnh viễn. Vui lòng mở Cài đặt ứng dụng để cấp quyền thủ công.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(ctx);
            },
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đăng xuất"),
        content: const Text("Bạn có chắc chắn muốn đăng xuất không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Đăng xuất", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  void _navigateToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );

    if (result == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _navigateToEditProfile,
                    child: _buildProfileHeader(),
                  ),
                  const SizedBox(height: 20),
                  if (_isAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageUsersScreen()));
                          },
                          icon: const Icon(Icons.admin_panel_settings),
                          label: const Text("QUẢN LÝ NHÂN VIÊN",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Cài đặt quyền truy cập",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildPermissionTile(
                                title: "Camera",
                                subtitle: "Để chụp ảnh ổ gà",
                                icon: Icons.camera_alt,
                                status: _permissions['Camera'],
                                onEnable: () => _requestSpecificPermission(Permission.camera),
                              ),
                              const Divider(height: 1),
                              _buildPermissionTile(
                                title: "Thư viện ảnh",
                                subtitle: "Để tải ảnh lên từ máy",
                                icon: Icons.photo_library,
                                status: _permissions['Thư viện ảnh'],
                                onEnable: _requestPhotoPermission,
                              ),
                              const Divider(height: 1),
                              _buildPermissionTile(
                                title: "Vị trí (GPS)",
                                subtitle: "Để xác định vị trí đường",
                                icon: Icons.location_on,
                                status: _permissions['Vị trí (GPS)'],
                                onEnable: () => _requestSpecificPermission(Permission.location),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: _handleLogout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                          elevation: 2,
                          side: BorderSide(color: Colors.red.shade100),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text("Đăng xuất", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Phiên bản 1.0.0", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Future<void> _loadDataFromFirestore() async {
    if (_user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          String dbName = userDoc.get('display_name') ?? "";
          log(dbName.toString());
          if (dbName.isNotEmpty) {
            userName = dbName;
          }
        });
      }
    } catch (e) {
      log("Lỗi lấy dữ liệu từ DB: $e");
    }
  }

  Widget _buildProfileHeader() {
    _user?.reload();
    ImageProvider avatarImage;
    if (_user?.photoURL != null && _user!.photoURL!.isNotEmpty) {
      avatarImage = NetworkImage(_user.photoURL!);
    } else {
      avatarImage = const AssetImage('images/place_holder_image.png');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF6C63FF),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  backgroundImage: avatarImage,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.edit, size: 16, color: Color(0xFF6C63FF)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        userName ?? "Người dùng",
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _user?.email ?? "Chưa cập nhật email",
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text("Chạm để chỉnh sửa", style: TextStyle(color: Colors.white, fontSize: 12)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required PermissionStatus? status,
    required VoidCallback onEnable,
  }) {
    bool isGranted = status?.isGranted ?? false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isGranted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isGranted ? Colors.green : Colors.orange, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      trailing: isGranted
          ? const Icon(Icons.check_circle, color: Colors.green)
          : SizedBox(
              height: 35,
              child: ElevatedButton(
                onPressed: onEnable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                ),
                child: const Text("Cấp quyền", style: TextStyle(fontSize: 12)),
              ),
            ),
    );
  }
}
