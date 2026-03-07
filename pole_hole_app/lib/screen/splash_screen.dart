import 'package:flutter/material.dart';

import '../service/auth_service.dart';
import 'login_screen.dart';
import 'main_screen.dart'; // Màn hình chính chứa bản đồ

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    bool isValidUser = await AuthService().checkAuthStatusOnAppStart();

    if (!mounted) return;

    if (isValidUser) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (context) => const AuthScreen()) // Thay bằng tên class login của bạn
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      ),
    );
  }
}
