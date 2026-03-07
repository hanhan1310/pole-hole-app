import 'dart:developer';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _surveyors = [];
  String? _selectedSurveyorId;
  late Stream<QuerySnapshot> _reportsStream;

  int? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    _reportsStream = _firebaseService.getReports();
    _checkRole();
  }

  Future<void> _checkRole() async {
    if (_currentUser == null) return;
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        String role = userDoc.get('role') ?? 'surveyor';
        setState(() {
          _isAdmin = (role == 'admin');
        });

        if (_isAdmin) {
          _fetchSurveyors();
        }
      }
    } catch (e) {
      log("Error check role: $e");
    }
  }

  Future<void> _fetchSurveyors() async {
    try {
      var snapshot = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'surveyor').get();

      setState(() {
        _surveyors = snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'name': doc['display_name'] ?? doc['email'] ?? 'Nhân viên',
          };
        }).toList();
      });
    } catch (e) {
      log("Lỗi lấy danh sách nhân viên: $e");
    }
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}";
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _customDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C63FF),
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
        _statsFilter = 'Tùy chọn';
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
      return date.isAfter(_customDateRange!.start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
    }
    return false;
  }

  Widget _buildHistoryItem(ReportModel report) {
    Color statusColor;
    String statusText;

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
            builder: (context) => ReportDetailScreen(report: report),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 70,
                height: 70,
                child: report.imageUrl.isNotEmpty
                    ? Image.network(report.imageUrl, fit: BoxFit.cover)
                    : Container(color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.addressStart,
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
                        _formatDate(report.createdAt),
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
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${report.potholeCount} ổ gà",
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
    final currentUid = _currentUser?.uid;

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
        stream: _reportsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          int redCount = 0;
          int yellowCount = 0;
          int greenCount = 0;

          List<ReportModel> reports = [];
          List<ReportModel> filteredReportsForList = [];

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final allReports = snapshot.data!.docs.map((doc) => ReportModel.fromFirestore(doc)).toList();

            reports = allReports.where((report) {
              if (_isAdmin) {
                if (_selectedSurveyorId != null) {
                  if (report.userId != _selectedSurveyorId) return false;
                }
              } else {
                if (report.userId != currentUid) return false;
              }

              return _isWithinFilter(report.createdAt);
            }).toList();

            for (var report in reports) {
              if (report.statusCode == 3) {
                redCount++;
              } else if (report.statusCode == 2) {
                yellowCount++;
              } else {
                greenCount++;
              }
            }

            filteredReportsForList = reports.where((report) {
              if (_selectedStatusFilter != null) {
                return report.statusCode == _selectedStatusFilter;
              }
              return true;
            }).toList();
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
                          labelStyle:
                              TextStyle(color: isSel ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                          onSelected: (val) {
                            if (e == 'Tùy chọn') {
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
                        Text("$total", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tỉ lệ ổ gà phát hiện được',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          if (_selectedStatusFilter != null)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedStatusFilter = null;
                                });
                              },
                              child: const Text("Hiển thị tất cả", style: TextStyle(color: Color(0xFF6C63FF))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCard(
                              "Nguy hiểm", "${(redPercent * 100).toStringAsFixed(0)}%", const Color(0xFFD9534F), 3),
                          _buildStatCard(
                              "Cảnh báo", "${(yellowPercent * 100).toStringAsFixed(0)}%", const Color(0xFFF0AD4E), 2),
                          _buildStatCard(
                              "An toàn", "${(greenPercent * 100).toStringAsFixed(0)}%", const Color(0xFF5CB85C), 1),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Lịch sử phát hiện",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      if (_isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedSurveyorId,
                              hint: const Text("Tất cả nhân viên", style: TextStyle(fontSize: 12)),
                              icon: const Icon(Icons.filter_list, size: 18, color: Color(0xFF6C63FF)),
                              style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w500),
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedSurveyorId = newValue;
                                });
                              },
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text("Tất cả nhân viên"),
                                ),
                                ..._surveyors.map<DropdownMenuItem<String>>((Map<String, dynamic> surveyor) {
                                  return DropdownMenuItem<String>(
                                    value: surveyor['id'],
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 120),
                                      child: Text(
                                        surveyor['name'],
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                filteredReportsForList.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Text("Không có báo cáo nào cho trạng thái này.", style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredReportsForList.length,
                        itemBuilder: (context, index) {
                          final reportItem = filteredReportsForList[index];
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

  Widget _buildStatCard(String label, String value, Color color, int statusCode) {
    bool isSelected = _selectedStatusFilter == statusCode;

    return InkWell(
      onTap: () {
        setState(() {
          if (_selectedStatusFilter == statusCode) {
            _selectedStatusFilter = null;
          } else {
            _selectedStatusFilter = statusCode;
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 90,
        height: 90,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
                color: isSelected ? color.withOpacity(0.3) : color.withOpacity(0.1),
                blurRadius: isSelected ? 15 : 10,
                offset: const Offset(0, 5))
          ],
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
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
