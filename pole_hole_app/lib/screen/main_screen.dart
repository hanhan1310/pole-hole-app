import 'package:flutter/material.dart';

import 'package:pole_hole_app/screen/map_tracking_screen.dart';
import 'package:pole_hole_app/screen/report_screen.dart';
import 'package:pole_hole_app/screen/setting_screen.dart';
import 'package:pole_hole_app/screen/update_road_data_screen.dart';


class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isHideBottomBar = false; // Biến trạng thái mới

  late AnimationController _pulseController;


  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      MapTrackingScreen(
        onTrackingChanged: (isTracking) {
          setState(() {
            _isHideBottomBar = isTracking; // Cập nhật trạng thái ẩn/hiện
          });
        },
      ),
      const UpdateRoadDataScreen(),
      const ReportScreen(),
      const SettingScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: _isHideBottomBar ? null :
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: const Color(0xFF6C63FF),
            unselectedLabelStyle: TextStyle(color: Colors.grey[400]),
            unselectedItemColor: Colors.grey[400],
            showUnselectedLabels: true,
            showSelectedLabels: true,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map_rounded), label: 'Giám sát'),
              BottomNavigationBarItem(icon: Icon(Icons.add_a_photo_outlined), activeIcon: Icon(Icons.add_a_photo_rounded), label: 'Báo cáo'),
              BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), activeIcon: Icon(Icons.pie_chart_rounded), label: 'Thống kê'),
              BottomNavigationBarItem(icon: Icon(Icons.security_outlined), activeIcon: Icon(Icons.security), label: 'Quyền'),
            ],
          ),
        ),
      ),

    );
  }
}

