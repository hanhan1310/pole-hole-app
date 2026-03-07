import 'package:flutter/material.dart';
import 'package:pole_hole_app/screen/map_tracking_screen.dart';
import 'package:pole_hole_app/screen/personal_screen.dart';
import 'package:pole_hole_app/screen/report_screen.dart';
import 'package:pole_hole_app/screen/update_road_data_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isHideBottomBar = false;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      MapTrackingScreen(
        onTrackingChanged: (isTracking) {
          // Dùng Future.microtask để tránh lỗi setState khi đang build
          if (mounted) {
            setState(() {
              _isHideBottomBar = isTracking;
            });
          }
        },
      ),
      const UpdateRoadDataScreen(),
      const ReportScreen(),
      const UserProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      extendBody: true,
      resizeToAvoidBottomInset: false, // Giữ false để Map không bị đẩy lên khi bàn phím hiện
      body: pages[_currentIndex],

      // SỬA: Nếu cần ẩn, set null cho toàn bộ bottomNavigationBar để mất hẳn Container
      bottomNavigationBar: _isHideBottomBar
          ? null
          : Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BottomNavigationBar(
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
                    BottomNavigationBarItem(
                      icon: Icon(Icons.map_outlined),
                      activeIcon: Icon(Icons.map_rounded),
                      label: 'Giám sát',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.add_a_photo_outlined),
                      activeIcon: Icon(Icons.add_a_photo_rounded),
                      label: 'Báo cáo',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.pie_chart_outline),
                      activeIcon: Icon(Icons.pie_chart_rounded),
                      label: 'Thống kê',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person_rounded),
                      label: 'Cá nhân',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
