import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../service/api_service.dart';

class EditUserScreen extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;

  const EditUserScreen({super.key, required this.uid, required this.userData});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final PotholeService _potholeService = PotholeService();

  late TextEditingController _nameController;
  late TextEditingController _emailController;

  String _currentStatus = 'active';
  bool _isApproved = false;

  File? _pickedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userData['display_name'] ?? "");
    _emailController = TextEditingController(text: widget.userData['email'] ?? "");
    _currentStatus = widget.userData['status'] ?? 'active';
    _isApproved = widget.userData['is_approved'] ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedImage = File(image.path);
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      String? newPhotoUrl;

      if (_pickedImage != null) {
        newPhotoUrl = await _potholeService.uploadImageToCloudinary(_pickedImage!);
        if (newPhotoUrl == null) {
          throw Exception("Lỗi upload ảnh. Vui lòng thử lại.");
        }
      }

      Map<String, dynamic> updateData = {
        'display_name': _nameController.text.trim(),
        'status': _currentStatus,
        'is_approved': _isApproved,
        if (newPhotoUrl != null) 'photo_url': newPhotoUrl,
      };

      await FirebaseFirestore.instance.collection('users').doc(widget.uid).update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Cập nhật thông tin thành công!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider avatarImage;
    if (_pickedImage != null) {
      avatarImage = FileImage(_pickedImage!);
    } else if (widget.userData['photo_url'] != null && widget.userData['photo_url'] != "") {
      avatarImage = NetworkImage(widget.userData['photo_url']);
    } else {
      avatarImage = const AssetImage('images/place_holder_image.png');
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Sửa nhân viên", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade200, width: 3),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: avatarImage,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6C63FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildTextField("Email (Chỉ xem)", _emailController, readOnly: true, icon: Icons.email_outlined),
                  _buildTextField(
                    "Tên hiển thị (Chỉ xem)",
                    _nameController,
                    icon: Icons.person_outline,
                    readOnly: true,
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Quản lý tài khoản", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Icon(_currentStatus == 'active' ? Icons.check_circle : Icons.block,
                            color: _currentStatus == 'active' ? Colors.green : Colors.red),
                        const SizedBox(width: 15),
                        const Text("Trạng thái:", style: TextStyle(fontSize: 16)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _currentStatus,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: 'active',
                                child: Text("Hoạt động",
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                            DropdownMenuItem(
                                value: 'locked',
                                child: Text("Bị khóa",
                                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DropdownMenuItem(
                                value: 'deleted',
                                child:
                                    Text("Đã xóa", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _currentStatus = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Container(
                  //   padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  //   decoration: BoxDecoration(
                  //     border: Border.all(color: Colors.grey.shade300),
                  //     borderRadius: BorderRadius.circular(15),
                  //   ),
                  //   child: Row(
                  //     children: [
                  //       const Icon(Icons.verified_user, color: Colors.blue),
                  //       const SizedBox(width: 15),
                  //       const Expanded(child: Text("Đã phê duyệt vào dự án:", style: TextStyle(fontSize: 16))),
                  //       Switch(
                  //         value: _isApproved,
                  //         activeColor: const Color(0xFF6C63FF),
                  //         onChanged: (val) => setState(() => _isApproved = val),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 5,
                      ),
                      child: const Text("LƯU CẬP NHẬT",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false, IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}
