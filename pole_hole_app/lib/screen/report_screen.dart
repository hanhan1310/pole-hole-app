import 'dart:developer';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../model/report_model.dart';
import '../service/firebase_service.dart';
import 'detail_report_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _statsFilter = 'Ngày';
  final FirebaseService _firebaseService = FirebaseService();
  DateTimeRange? _customDateRange;

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}";
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _customDateRange, // Mặc định chọn range cũ nếu có
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C63FF), // Màu chủ đạo
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _statsFilter = 'Tùy chọn'; // Chuyển filter sang chế độ tùy chọn
      });
    }
  }

  bool _isWithinFilter(DateTime date) {
    final now = DateTime.now();

    if (_statsFilter == 'Ngày') {
      return date.year == now.year && date.month == now.month && date.day == now.day;
    } else if (_statsFilter == 'Tuần') {
      return now.difference(date).inDays <= 7;
    } else if (_statsFilter == 'Tháng') {
      return date.year == now.year && date.month == now.month;
    } else if (_statsFilter == 'Tùy chọn' && _customDateRange != null) {
      // Logic lọc theo khoảng tùy chọn
      // isAfter start (trừ 1s để lấy cả mốc bắt đầu) VÀ isBefore end (cộng 1 ngày để lấy hết ngày kết thúc)
      return date.isAfter(_customDateRange!.start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
    }
    return false;
  }

  Widget _buildHistoryItem(ReportModel report) {
    Color statusColor;
    String statusText;

    // Dùng report.statusCode gợi ý code sướng tay
    if (report.statusCode == 3) {
      statusColor = const Color(0xFFD9534F);
      statusText = "Nguy hiểm";
    } else if (report.statusCode == 2) {
      statusColor = const Color(0xFFF0AD4E);
      statusText = "Cảnh báo";
    } else {
      statusColor = const Color(0xFF5CB85C);
      statusText = "Tốt";
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReportDetailScreen(report: report), // Truyền model sang
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 3),
            )
          ],
          border: Border(left: BorderSide(color: statusColor, width: 5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ảnh thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 70,
                height: 70,
                child: report.imageUrl.isNotEmpty
                    ? Image.network(report.imageUrl, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
              ),
            ),
            const SizedBox(width: 12),

            // Thông tin
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.addressStart, // Dùng model
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(report.createdAt), // Dùng model
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                              color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${report.potholeCount} ổ gà", // Dùng model
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          title: const Text(
            "Thống kê dữ liệu",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 25),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.black),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firebaseService.getReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          int redCount = 0;
          int yellowCount = 0;
          int greenCount = 0;

          List<ReportModel> reports = [];

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final allReports =
                snapshot.data!.docs.map((doc) => ReportModel.fromFirestore(doc)).toList();

            reports = allReports.where((report) {
              return _isWithinFilter(report.createdAt);
            }).toList();

            log("Tổng số bản ghi sau lọc: ${reports.length}");
            for (var item in reports) {
              log(item.toString());
            }
            for (var report in reports) {
              if (report.statusCode == 3) {
                redCount++;
              } else if (report.statusCode == 2) {
                yellowCount++;
              } else {
                greenCount++;
              }
            }
          }

          int total = reports.length;
          double redPercent = total == 0 ? 0 : redCount / total;
          double yellowPercent = total == 0 ? 0 : yellowCount / total;
          double greenPercent = total == 0 ? 0 : greenCount / total;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: ["Ngày", "Tuần", "Tháng", "Tùy chọn"].map((e) {
                      bool isSel = _statsFilter == e;

                      String label = e;
                      if (e == 'Tùy chọn' && _customDateRange != null) {
                        label =
                            "${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}";
                      }

                      return Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: isSel,
                          checkmarkColor: Colors.white,
                          selectedColor: const Color(0xFF6C63FF),
                          backgroundColor: Colors.grey[100],
                          labelStyle: TextStyle(
                              color: isSel ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold),
                          onSelected: (val) {
                            if (e == 'Tùy chọn') {
                              // Nếu bấm Tùy chọn thì mở lịch
                              _pickDateRange();
                            } else {
                              setState(() => _statsFilter = e);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Pie Chart
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 250,
                      width: 250,
                      child: CustomPaint(
                        painter: ThreeDPieChartPainter(
                          redPercent: redPercent,
                          yellowPercent: yellowPercent,
                          greenPercent: greenPercent,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.analytics, color: Colors.grey),
                        Text("TỔNG", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        Text("$total",
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),

                const SizedBox(height: 30),

                // Legend Cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 15),
                        child: Text(
                          'Tỉ lệ ổ gà phát hiện được',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCard("Nhiều", "${(redPercent * 100).toStringAsFixed(0)}%",
                              const Color(0xFFD9534F)),
                          _buildStatCard("Ít", "${(yellowPercent * 100).toStringAsFixed(0)}%",
                              const Color(0xFFF0AD4E)),
                          _buildStatCard("Không", "${(greenPercent * 100).toStringAsFixed(0)}%",
                              const Color(0xFF5CB85C)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Text(
                    "Lịch sử phát hiện",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),

                const SizedBox(height: 10),

                ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final reportItem = reports[index];
                    return _buildHistoryItem(reportItem);
                  },
                ),

                const SizedBox(height: 50),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      width: 90,
      height: 90,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 5),
          Text(label,
              style:
                  const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

class ThreeDPieChartPainter extends CustomPainter {
  final double redPercent;
  final double yellowPercent;
  final double greenPercent;

  ThreeDPieChartPainter({
    required this.redPercent,
    required this.yellowPercent,
    required this.greenPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 80) / 2;
    const double strokeWidth = 35.0;
    const double gapSize = 0.45;

    final segments = [
      if (redPercent > 0) _PieSegment(redPercent, const Color(0xFFD9534F)),
      if (yellowPercent > 0) _PieSegment(yellowPercent, const Color(0xFFF0AD4E)),
      if (greenPercent > 0) _PieSegment(greenPercent, const Color(0xFF5CB85C)),
    ];

    double startAngle = -math.pi / 2;

    if (segments.isEmpty) {
      final bgPaint = Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, radius, bgPaint);
    }

    for (var segment in segments) {
      final sweepAngle = segment.value * 2 * math.pi;
      final double gap = (segments.length > 1) ? gapSize : 0.0;
      final drawAngle = sweepAngle - gap;

      if (drawAngle > 0) {
        final paint = Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle + (gap / 2),
          drawAngle,
          false,
          paint,
        );
      }
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant ThreeDPieChartPainter oldDelegate) {
    return oldDelegate.redPercent != redPercent ||
        oldDelegate.yellowPercent != yellowPercent ||
        oldDelegate.greenPercent != greenPercent;
  }
}

class _PieSegment {
  final double value;
  final Color color;
  _PieSegment(this.value, this.color);
}
