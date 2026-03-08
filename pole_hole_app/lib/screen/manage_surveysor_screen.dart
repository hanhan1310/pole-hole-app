import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pole_hole_app/widget/show_toast.dart';

import 'edit_user_screen.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  // Logic xử lý hành động của Admin (Xóa/Khóa/Sửa)
  Future<void> _handleAdminAction(String action, String targetUid, Map<String, dynamic> currentData) async {
    try {
      if (action == 'delete') {
        await FirebaseFirestore.instance.collection('users').doc(targetUid).update({'status': 'deleted'});
        if (mounted) ShowToast("Đã xóa tài khoản", true);
      } else if (action == 'lock') {
        String currentStatus = currentData['status'] ?? 'active';
        String newStatus = currentStatus == 'locked' ? 'active' : 'locked';
        await FirebaseFirestore.instance.collection('users').doc(targetUid).update({'status': newStatus});
        if (mounted) {
          ShowToast(newStatus == 'locked' ? "Đã khóa tài khoản" : "Đã mở khóa tài khoản", true);
        }
      } else if (action == 'edit') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditUserScreen(uid: targetUid, userData: currentData),
          ),
        );
      }
    } catch (e) {
      if (mounted) ShowToast("Có lỗi xảy ra", false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Danh sách nhân viên", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF6C63FF),
        iconTheme: const IconThemeData(color: Colors.white), // Nút back màu trắng
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Chỉ lấy user không phải admin
        stream: FirebaseFirestore.instance.collection('users').where('role', isNotEqualTo: 'admin').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Chưa có nhân viên nào."));
          }

          var users = snapshot.data!.docs;
          // Lọc phía client để ẩn những người đã bị xóa (deleted)
          users = users.where((d) => d.get('status') != 'deleted').toList();

          if (users.isEmpty) {
            return const Center(child: Text("Chưa có nhân viên nào (Active)."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(15),
            itemCount: users.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              var data = users[i].data() as Map<String, dynamic>;
              String uid = users[i].id;
              String name = data['display_name'] ?? data['email'] ?? 'User';
              String email = data['email'] ?? '';
              String status = data['status'] ?? 'active';
              bool isLocked = status == 'locked';
              bool isOnline = data['online'] ?? false; // Lấy trạng thái online

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 3))
                  ],
                  border: isLocked ? Border.all(color: Colors.orange.withOpacity(0.5)) : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: data['photo_url'] != null && data['photo_url'].isNotEmpty
                            ? NetworkImage(data['photo_url'])
                            : null,
                        child: (data['photo_url'] == null || data['photo_url'].isEmpty)
                            ? const Icon(Icons.person, color: Colors.grey)
                            : null,
                      ),
                      // Chấm xanh báo online
                      if (isOnline)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isLocked ? Colors.grey : Colors.black87,
                      decoration: isLocked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (isLocked)
                        const Text("ĐANG BỊ KHÓA",
                            style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    itemBuilder: (c) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit, color: Colors.blue, size: 20),
                          SizedBox(width: 10),
                          Text('Sửa thông tin')
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'lock',
                        child: Row(children: [
                          Icon(isLocked ? Icons.lock_open : Icons.lock,
                              color: isLocked ? Colors.green : Colors.orange, size: 20),
                          const SizedBox(width: 10),
                          Text(isLocked ? 'Mở khóa' : 'Khóa tài khoản')
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, color: Colors.red, size: 20),
                          SizedBox(width: 10),
                          Text('Xóa tài khoản')
                        ]),
                      ),
                    ],
                    onSelected: (val) => _handleAdminAction(val, uid, data),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
