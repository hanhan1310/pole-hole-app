import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../service/auth_service.dart';
import '../widget/show_toast.dart';
import 'main_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  // Biến này để điều khiển UI
  bool _isLoginTab = true;

  // Controllers
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _isLoginTab = _tabController.index == 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1. Ẩn bàn phím để trải nghiệm tốt hơn
    FocusScope.of(context).unfocus();

    // 2. Validate cơ bản
    if (_emailController.text.isEmpty || _passController.text.isEmpty) {
      ShowToast("Vui lòng nhập Email và Mật khẩu", false);
      return;
    }

    if (!_isLoginTab) {
      if (_passController.text != _confirmPassController.text) {
        ShowToast("Mật khẩu xác nhận không khớp", false);
        return;
      }
      if (_codeController.text.isEmpty) {
        ShowToast("Vui lòng nhập mã dự án", false);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isLoginTab) {
        await _authService.signIn(
          email: _emailController.text.trim(),
          password: _passController.text.trim(),
        );
      } else {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passController.text.trim(),
          inviteCode: _codeController.text.trim(),
        );
        ShowToast('Đăng ký vào dự án thành công', true);
      }

      if (mounted) {
        Navigator.of(context)
            .pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Lỗi: ${e.message}";
      if (e.code == 'user-not-approved') msg = "Tài khoản chưa được duyệt hoặc mã sai.";
      if (e.code == 'user-disabled') msg = "Tài khoản đã bị khóa.";
      if (e.code == 'invalid-invite-code') msg = "Mã dự án không chính xác.";
      if (e.code == 'email-already-in-use') msg = "Email này đã được sử dụng.";
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') msg = "Sai email hoặc mật khẩu.";
      if (e.code == 'unknown-error') msg = "Lỗi hệ thống";

      ShowToast(msg, false);
    } catch (e) {
      ShowToast("Có lỗi xảy ra", false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 30),

                // TAB SWITCHER
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      setState(() {
                        _isLoginTab = (index == 0);
                      });
                    },
                    indicator: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    overlayColor: MaterialStateProperty.all(Colors.transparent),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: const [
                      Tab(text: "Đăng nhập"),
                      Tab(text: "Đăng ký"),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // FORM INPUT
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Column(
                    children: [
                      _buildFancyField("Tài khoản", Icons.email_outlined, _emailController),
                      _buildFancyField("Mật khẩu", Icons.lock_outline, _passController, isPassword: true),
                      if (!_isLoginTab) ...[
                        _buildFancyField("Nhập lại mật khẩu", Icons.lock_reset, _confirmPassController,
                            isPassword: true),
                        const SizedBox(height: 10),
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: TextField(
                            controller: _codeController,
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              labelText: "Mã Dự Án (Bắt buộc)",
                              labelStyle: TextStyle(color: Colors.orange),
                              prefixIcon: Icon(Icons.vpn_key, color: Colors.orange),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 5,
                      shadowColor: const Color(0xFF6C63FF).withOpacity(0.4),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            _isLoginTab ? "ĐĂNG NHẬP" : "ĐĂNG KÝ NGAY",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),

                if (_isLoginTab)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: TextButton(
                      onPressed: () {
                        // Thêm logic quên mật khẩu sau
                      },
                      child: const Text("Quên mật khẩu?", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          height: 100,
          width: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on_rounded, size: 50, color: Color(0xFF6C63FF)),
        ),
        const SizedBox(height: 20),
        const Text(
          "POLE HOLE",
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF6C63FF), letterSpacing: 2),
        ),
        Text("Hệ thống giám sát đường bộ", style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFancyField(String label, IconData icon, TextEditingController ctrl, {bool isPassword = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: TextField(
        controller: ctrl,
        obscureText: isPassword,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF6C63FF)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }
}
