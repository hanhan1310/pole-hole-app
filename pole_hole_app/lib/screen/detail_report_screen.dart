import 'dart:developer';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../model/report_model.dart';
import '../service/api_service.dart';

class ReportDetailScreen extends StatefulWidget {
  final ReportModel report;

  const ReportDetailScreen({super.key, required this.report});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  // Controllers
  final TextEditingController _addressStartController = TextEditingController();
  final TextEditingController _addressEndController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _dateController = TextEditingController(); // Ngày tạo

  // --- CONTROLLER MỚI ---
  final TextEditingController _updateTimeController = TextEditingController(); // Ngày cập nhật
  final TextEditingController _reviewerController = TextEditingController(); // Người tạo cũ
  final TextEditingController _updaterController = TextEditingController(); // Người cập nhật mới

  // Data
  Map<String, dynamic> _newData = {};
  String _currentStatus = 'green';
  String _repairStatus = 'pending';
  int _currentPotholeCount = 0;

  // Logic hiển thị
  Uint8List? _displayImageBytes;
  String? _oldImageUrl;

  // Biến lưu thời gian cập nhật thực tế để gửi lên server
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

    // --- ĐIỀN DỮ LIỆU NGƯỜI DÙNG ---
    _reviewerController.text = widget.report.originalReviewer;
    _updaterController.text = "Người đánh giá 2"; // Hardcode theo yêu cầu

    // --- ĐIỀN THỜI GIAN CẬP NHẬT (Mặc định là hiện tại) ---
    _selectedUpdateDate = DateTime.now();
    _updateTimeController.text = DateFormat('dd/MM/yyyy HH:mm').format(_selectedUpdateDate);

    _currentPotholeCount = widget.report.potholeCount;
    _oldImageUrl = widget.report.imageUrl;

    if (widget.report.statusCode == 3)
      _currentStatus = 'red';
    else if (widget.report.statusCode == 2)
      _currentStatus = 'yellow';
    else
      _currentStatus = 'green';

    _repairStatus = widget.report.repairStatus;
  }

  // Hàm chọn thời gian cập nhật
  Future<void> _selectUpdateTime() async {
    final DateTime now = DateTime.now();

    // 1. Chọn ngày
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedUpdateDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && mounted) {
      // 2. Chọn giờ
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

  void _calculateRepairStatus(int newCount) {
    int oldCount = widget.report.potholeCount;
    if (newCount == 0) {
      _repairStatus = 'fixed';
    } else if (newCount < oldCount) {
      _repairStatus = 'in_progress';
    } else {
      _repairStatus = 'pending';
    }
  }

  Future<void> _deleteReport() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: const Text("Bạn có chắc chắn muốn xóa báo cáo này không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Xóa", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('polehole').doc(widget.report.id).delete();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Đã xóa thành công")));
        }
      } catch (e) {
        log("Lỗi xóa: $e");
      }
    }
  }

  Future<void> _updateReport() async {
    try {
      // (Bỏ qua phần upload ảnh để code ngắn gọn, bạn tự thêm vào nếu cần)

      Map<String, dynamic> updateData = {
        'location_start': _addressStartController.text,
        'location_end': _addressEndController.text,
        'note': _noteController.text,
        'pothole_count': _currentPotholeCount,
        'repair_status': _repairStatus,
        'status': {
          'code': _currentStatus == 'red' ? 3 : (_currentStatus == 'yellow' ? 2 : 1),
          'text': _currentStatus.toUpperCase()
        },

        // --- CẬP NHẬT CÁC TRƯỜNG MỚI ---
        'updated_at': Timestamp.fromDate(_selectedUpdateDate), // Lưu thời gian user chọn
        'updater': _updaterController.text, // Lưu tên người cập nhật
        // 'original_reviewer': ... (Không cần update trường này, giữ nguyên)
      };

      await FirebaseFirestore.instance
          .collection('polehole')
          .doc(widget.report.id)
          .update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Cập nhật thành công!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      log("Lỗi update: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Lỗi: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title:
            const Text("Chi tiết & Cập nhật", style: TextStyle(color: Colors.white, fontSize: 20)),
        backgroundColor: const Color(0xFF6C63FF),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- ẢNH ---
            Container(
              height: 220,
              width: double.infinity,
              decoration:
                  BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _displayImageBytes != null
                    ? Image.memory(_displayImageBytes!, fit: BoxFit.contain)
                    : (_oldImageUrl != null && _oldImageUrl!.isNotEmpty
                        ? Image.network(_oldImageUrl!, fit: BoxFit.contain)
                        : const Center(
                            child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey))),
              ),
            ),
            const SizedBox(height: 20),

            // --- NÚT CHỤP ẢNH ---
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final XFile? img = await picker.pickImage(
                          source: ImageSource.camera, imageQuality: 50, maxWidth: 1024);
                      if (img != null && mounted) {
                        try {
                          dynamic response = await PotholeService().processImage(img, context);
                          if (response != null) {
                            setState(() {
                              _newData = response;
                              _displayImageBytes = response['imageBytes'];
                              _currentStatus = response['status'];
                              _currentPotholeCount = response['potholeCount'];
                              _calculateRepairStatus(_currentPotholeCount);
                            });
                          }
                        } catch (e) {
                          log("Lỗi AI: $e");
                        }
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Chụp cập nhật"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.photo_library),
                    label: const Text("Thư viện"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),

            // --- TRẠNG THÁI SỬA CHỮA ---
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _getRepairColor(_repairStatus).withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: _getRepairColor(_repairStatus)),
              ),
              child: Row(
                children: [
                  Icon(Icons.build_circle, color: _getRepairColor(_repairStatus), size: 30),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Tình trạng:", style: TextStyle(color: Colors.grey)),
                      Text(
                        _getRepairText(_repairStatus),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _getRepairColor(_repairStatus)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Cũ: ${widget.report.potholeCount}",
                          style: const TextStyle(color: Colors.grey)),
                      Text("Mới: $_currentPotholeCount",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- CÁC FIELD NHÂN SỰ (MỚI) ---
            Row(
              children: [
                Expanded(
                    child:
                        _buildReadOnlyField("Người đánh giá", Icons.person, _reviewerController)),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        _buildReadOnlyField("Người cập nhật", Icons.edit_note, _updaterController)),
              ],
            ),

            const SizedBox(height: 15),

            // --- CÁC FIELD THỜI GIAN ---
            Row(
              children: [
                // Ngày tạo (Readonly)
                Expanded(child: _buildReadOnlyField("Ngày tạo", Icons.history, _dateController)),
                const SizedBox(width: 10),
                // Ngày cập nhật (Editable)
                Expanded(
                  child: GestureDetector(
                    onTap: _selectUpdateTime, // Cho phép bấm vào để chọn giờ
                    child: AbsorbPointer(
                      // Chặn bàn phím hiện lên
                      child:
                          _buildEditableField("Cập nhật lúc", Icons.update, _updateTimeController),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),
            _buildEditableField("Địa điểm bắt đầu", Icons.location_on, _addressStartController),
            const SizedBox(height: 15),
            _buildEditableField("Địa điểm kết thúc", Icons.flag, _addressEndController),
            const SizedBox(height: 15),
            _buildEditableField("Ghi chú", Icons.note, _noteController, maxLines: 3),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _updateReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("LƯU CẬP NHẬT",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- Helpers ---
  Color _getRepairColor(String status) {
    switch (status) {
      case 'fixed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _getRepairText(String status) {
    switch (status) {
      case 'fixed':
        return "ĐÃ SỬA CHỮA";
      case 'in_progress':
        return "ĐANG SỬA CHỮA";
      default:
        return "CHƯA SỬA CHỮA";
    }
  }

  Widget _buildEditableField(String label, IconData icon, TextEditingController controller,
      {int maxLines = 1}) {
    return TextFormField(
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
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: TextStyle(color: Colors.grey[700], fontSize: 13), // Chữ nhỏ hơn xíu cho gọn
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
}
