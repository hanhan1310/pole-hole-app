import 'package:flutter/material.dart';
import 'dart:math' as math;

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _statsFilter = 'Ngày';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          title: const Text(
            "Thống kê dữ liệu",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500, fontSize: 25),
          ),
          centerTitle: true,
          backgroundColor: Color(0xFF6C63FF),
          foregroundColor: Colors.black),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Filter
            Container(
              height: 50,
              margin: const EdgeInsets.symmetric(vertical: 20),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: ["Ngày", "Tuần", "Tháng"].map((e) {
                  bool isSel = _statsFilter == e;
                  return Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: ChoiceChip(
                      label: Text(e),
                      selected: isSel,
                      checkmarkColor: Colors.white,
                      selectedColor: const Color(0xFF6C63FF),
                      backgroundColor: Colors.grey[100],
                      labelStyle: TextStyle(
                          color: isSel ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold),
                      onSelected: (val) => setState(() => _statsFilter = e),
                    ),
                  );
                }).toList(),
              ),
            ),

            // 3D PIE CHART AREA
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 300,
                  width: 300,
                  child: CustomPaint(
                    painter: ThreeDPieChartPainter(), // Painter 3D mới
                  ),
                ),
                // Center Hub Text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.analytics, color: Colors.grey),
                    Text("TỔNG",
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const Text("150",
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),

            const SizedBox(height: 40),

            // Legend Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15, left: 20),
                    child: Text('Tỉ lệ ổ gà phát hiện được', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard("Nhiều", "15%", const Color(0xFFD9534F)), // Red
                      _buildStatCard(
                          "Ít", "35%", const Color(0xFFF0AD4E)), // Orange
                      _buildStatCard(
                          "Không có", "50%", const Color(0xFF5CB85C)), // Green
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

class ThreeDPieChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 80) / 2;
    const double strokeWidth = 35.0;

    final segments = [
      _PieSegment(0.15, const Color(0xFFFF5252)), // Đỏ
      _PieSegment(0.35, const Color(0xFFFFB74D)), // Cam
      _PieSegment(0.50, const Color(0xFF26A69A)), // Xanh Teal
    ];

    double startAngle = -math.pi / 2;

    final bgPaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round; // Bo tròn nền luôn cho đồng bộ

    canvas.drawCircle(center, radius, bgPaint);

    for (var segment in segments) {
      final sweepAngle = segment.value * 2 * math.pi;

      final double gap = 0.35;
      final drawAngle = sweepAngle - gap;

      if (drawAngle > 0) {
        final paint = Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round; // Bo tròn đầu

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle + (gap / 2), // Dịch vào giữa
          drawAngle,
          false,
          paint,
        );
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Class Model đơn giản hóa (chỉ cần 1 màu)
class _PieSegment {
  final double value;
  final Color color;
  _PieSegment(this.value, this.color);
}
