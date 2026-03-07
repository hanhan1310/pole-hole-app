import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../model/report_model.dart';
import '../service/api_service.dart';

class ReportDetailScreen extends StatefulWidget {
  final ReportModel report;

  const ReportDetailScreen({super.key, required this.report});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final PotholeService _potholeService = PotholeService();

  final TextEditingController _addressStartController = TextEditingController();
  final TextEditingController _addressEndController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _updateTimeController = TextEditingController();
  final TextEditingController _reviewerController = TextEditingController();
  final TextEditingController _updaterController = TextEditingController();

  Map<String, dynamic> _aiResponseData = {};
  String _currentStatus = 'green';
  String _repairStatus = 'pending';
  int _currentPotholeCount = 0;
  bool _isLoading = false;

  Uint8List? _newImageBytes;
  String? _currentDisplayUrl;

  DateTime _selectedUpdateDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fillInitialData();
  }

  void _fillInitialData() {
    _addressStartController.text = widget.report.addressStart;
    _addressEndController.text = widget.report.addressEnd ?? '';
    _noteController.text = widget.report.note ?? '';
    _dateController.text = DateFormat('dd/MM/yyyy HH:mm').format(widget.report.createdAt);

    _reviewerController.text = widget.report.originalReviewer;
    final user = FirebaseAuth.instance.currentUser;
    String updaterName = user?.displayName ?? user?.email ?? "Admin";
    _updaterController.text = updaterName;
    _selectedUpdateDate = DateTime.now();
    _updateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(_selectedUpdateDate);

    _currentPotholeCount = widget.report.potholeCount;
    _currentDisplayUrl = widget.report.imageUrl;
    _repairStatus = widget.report.repairStatus;

    if (widget.report.statusCode == 3) {
      _currentStatus = 'red';
    } else if (widget.report.statusCode == 2) {
      _currentStatus = 'yellow';
    } else {
      _currentStatus = 'green';
    }
  }

  Future<void> _handleImageInput(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? img = await picker.pickImage(
      source: source,
      imageQuality: 50,
      maxWidth: 1024,
    );

    if (img != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Đang phân tích AI..."), duration: Duration(seconds: 1)),
      );

      try {
        dynamic response = await _potholeService.processImage(img, context);
        if (response != null) {
          setState(() {
            _aiResponseData = response;
            _newImageBytes = response['imageBytes'];
            _currentStatus = response['status'];

            int newCount = response['potholeCount'] ?? 0;
            _currentPotholeCount = newCount;

            int originalCount = widget.report.potholeCount;
            if (newCount == 0 || (originalCount > 0 && newCount <= (originalCount / 3))) {
              _repairStatus = 'fixed';
            } else {
              _repairStatus = 'pending';
            }
          });
        }
      } catch (e) {
        log("Lỗi AI: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi xử lý ảnh: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveUpdate() async {
    if (_newImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng chụp ảnh mới để cập nhật!"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final tempDir = await getTemporaryDirectory();
      File tempFile = await File('${tempDir.path}/update_${DateTime.now().millisecondsSinceEpoch}.jpg').create();
      await tempFile.writeAsBytes(_newImageBytes!);

      String? newImageUrl = await _potholeService.uploadImageToCloudinary(tempFile);

      if (newImageUrl == null) throw Exception("Không thể upload ảnh");

      Map<String, dynamic> historyItem = {
        'image_url': newImageUrl,
        'updated_at': Timestamp.fromDate(_selectedUpdateDate),
        'pothole_count': _currentPotholeCount,
        'status_code': _currentStatus == 'red' ? 3 : (_currentStatus == 'yellow' ? 2 : 1),
        'updater': _updaterController.text,
        'repair_status': _repairStatus,
      };

      await FirebaseFirestore.instance.collection('polehole').doc(widget.report.id).update({
        'image': newImageUrl,
        'pothole_count': _currentPotholeCount,
        'repair_status': _repairStatus,
        'updated_at': Timestamp.fromDate(_selectedUpdateDate),
        'updater': _updaterController.text,
        'note': _noteController.text,
        'status': {
          'code': _currentStatus == 'red' ? 3 : (_currentStatus == 'yellow' ? 2 : 1),
          'text': _currentStatus.toUpperCase()
        },
        'history_updates': FieldValue.arrayUnion([historyItem]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Cập nhật thành công!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      log("Lỗi Update: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectUpdateTime() async {
    final DateTime now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedUpdateDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null && mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedUpdateDate),
      );
      if (pickedTime != null) {
        setState(() {
          _selectedUpdateDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _updateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(_selectedUpdateDate);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Cập nhật hiện trường", style: TextStyle(color: Colors.white, fontSize: 20)),
        backgroundColor: const Color(0xFF6C63FF),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _newImageBytes != null
                          ? Image.memory(_newImageBytes!, fit: BoxFit.cover)
                          : (_currentDisplayUrl != null
                              ? Image.network(_currentDisplayUrl!, fit: BoxFit.cover)
                              : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSmallButton("Chụp cập nhật", Icons.camera_alt, Colors.blue,
                            () => _handleImageInput(ImageSource.camera)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildSmallButton("Thư viện", Icons.photo_library, Colors.purple,
                            () => _handleImageInput(ImageSource.gallery)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const Text("Đánh giá AI:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _getRepairColor(_repairStatus).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _getRepairColor(_repairStatus)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.analytics, color: _getRepairColor(_repairStatus), size: 30),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_getRepairText(_repairStatus),
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _getRepairColor(_repairStatus))),
                              const SizedBox(height: 5),
                              Text("Ổ gà gốc: ${widget.report.potholeCount}  ➔  Hiện tại: $_currentPotholeCount",
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _buildReadOnlyField("Người tạo", Icons.person, _reviewerController)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildReadOnlyField("Người cập nhật", Icons.edit, _updaterController)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _selectUpdateTime,
                    child: AbsorbPointer(
                      child: _buildEditableField("Thời gian cập nhật", Icons.update, _updateTimeController),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildEditableField("Ghi chú tiến độ", Icons.note, _noteController, maxLines: 2),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _saveUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("LƯU CẬP NHẬT & ĐÁNH GIÁ",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Divider(thickness: 2),
                  const Text("Lịch sử hình ảnh", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  const Text("Lướt ngang để xem các lần cập nhật trước",
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 15),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('polehole').doc(widget.report.id).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var docData = snapshot.data!.data() as Map<String, dynamic>?;
                      List<dynamic> history =
                          docData != null && docData.containsKey('history_updates') ? docData['history_updates'] : [];

                      if (history.isEmpty) {
                        return Container(
                          height: 100,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                          child: const Text("Chưa có lịch sử cập nhật nào.", style: TextStyle(color: Colors.grey)),
                        );
                      }

                      return SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            var item = history[index];
                            String imageUrl = item['image_url'] ?? '';
                            Timestamp? ts = item['updated_at'];
                            String timeStr = ts != null ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : 'N/A';
                            int count = item['pothole_count'] ?? 0;

                            return Container(
                              width: 160,
                              margin: const EdgeInsets.only(right: 15),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(timeStr,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text("Ổ gà: $count", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }

  Widget _buildSmallButton(String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _buildEditableField(String label, IconData icon, TextEditingController controller, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF6C63FF)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, IconData icon, TextEditingController controller) {
    return TextField(
      controller: controller,
      readOnly: true,
      style: TextStyle(color: Colors.grey[600], fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Color _getRepairColor(String status) {
    if (status == 'fixed') return Colors.green;
    if (status == 'in_progress') return Colors.blue;
    return Colors.orange;
  }

  String _getRepairText(String status) {
    if (status == 'fixed') return "ĐÃ SỬA CHỮA";
    if (status == 'in_progress') return "ĐANG SỬA CHỮA";
    return "CHƯA SỬA CHỮA";
  }
}
