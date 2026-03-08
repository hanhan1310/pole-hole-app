import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../service/api_service.dart';
import '../widget/show_toast.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final PotholeService _potholeService = PotholeService();

  late TextEditingController _nameController;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _oldPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  File? _pickedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    log(FirebaseAuth.instance.currentUser.toString());
    log(_user.toString());
    _nameController = TextEditingController(text: _user?.displayName ?? '');

    _emailController.text = _user?.email ?? "";
    _loadDataFromFirestore();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _oldPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _loadDataFromFirestore() async {
    if (_user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      log(userDoc.toString());
      if (userDoc.exists && mounted) {
        setState(() {
          String dbName = userDoc.get('display_name') ?? "";
          log(dbName.toString());
          if (dbName.isNotEmpty) {
            _nameController = TextEditingController(text: dbName);
          }
        });
      }
    } catch (e) {
      log("Lỗi lấy dữ liệu từ DB: $e");
    }
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
    if (_user == null) return;

    setState(() => _isLoading = true);
    try {
      String? newPhotoUrl = _user!.photoURL;
      String newName = _nameController.text.trim();

      if (_pickedImage != null) {
        log(_pickedImage.toString());
        String? uploadedUrl = await _potholeService.uploadImageToCloudinary(_pickedImage!);
        log(uploadedUrl.toString());
        if (uploadedUrl != null) {
          newPhotoUrl = uploadedUrl;
        }
      }

      if (newName != _user!.displayName || newPhotoUrl != _user!.photoURL) {
        if (newPhotoUrl != null) await _user!.updatePhotoURL(newPhotoUrl);
        if (newName.isNotEmpty) await _user!.updateDisplayName(newName);
        log(newPhotoUrl.toString());
        await FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
          if (newPhotoUrl != null) 'photo_url': newPhotoUrl,
          if (newName.isNotEmpty) 'display_name': newName,
        });
      }

      if (_newPassController.text.isNotEmpty) {
        if (_oldPassController.text.isEmpty) {
          throw FirebaseAuthException(
              code: 'requires-recent-login', message: "Cần nhập mật khẩu cũ để đổi mật khẩu mới.");
        }
        if (_newPassController.text != _confirmPassController.text) {
          throw FirebaseAuthException(code: 'password-mismatch', message: "Mật khẩu xác nhận không khớp.");
        }

        AuthCredential credential =
            EmailAuthProvider.credential(email: _user!.email!, password: _oldPassController.text);
        await _user!.reauthenticateWithCredential(credential);

        await _user!.updatePassword(_newPassController.text);
      }

      await _user!.reload();

      if (mounted) {
        ShowToast("Cập nhật thành công", true);
        Navigator.pop(context, true);
      }
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? "Lỗi cập nhật";
      if (e.code == 'wrong-password') msg = "Mật khẩu cũ không đúng.";
      if (mounted) {
        ShowToast(msg, false);
      }
    } catch (e) {
      if (mounted) {
        ShowToast('Có lỗi xảy ra', false);
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
    } else if (_user?.photoURL != null && _user!.photoURL!.isNotEmpty) {
      avatarImage = NetworkImage(_user!.photoURL!);
    } else {
      avatarImage = const AssetImage('images/place_holder_image.png');
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Chỉnh sửa hồ sơ", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                            backgroundColor: Colors.white,
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
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildTextField("Email", _emailController, readOnly: true, icon: Icons.email_outlined),
                  _buildTextField("Tên hiển thị", _nameController, icon: Icons.person_outline),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Đổi mật khẩu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const SizedBox(height: 10),
                  _buildTextField("Mật khẩu cũ", _oldPassController, isPass: true, icon: Icons.lock_outline),
                  _buildTextField("Mật khẩu mới", _newPassController, isPass: true, icon: Icons.vpn_key_outlined),
                  _buildTextField("Nhập lại mật khẩu mới", _confirmPassController,
                      isPass: true, icon: Icons.lock_reset),
                  const SizedBox(height: 30),
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
                      child: const Text("LƯU THAY ĐỔI",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool isPass = false, bool readOnly = false, IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPass,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}
