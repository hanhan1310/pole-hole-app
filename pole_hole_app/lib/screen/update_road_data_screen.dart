import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;


import '../service/api_service.dart';
import 'dart:typed_data';

class UpdateRoadDataScreen extends StatefulWidget {
  const UpdateRoadDataScreen({super.key});

  @override
  State<UpdateRoadDataScreen> createState() => _UpdateRoadDataScreenState();
}

class _UpdateRoadDataScreenState extends State<UpdateRoadDataScreen> {
  Map<String, dynamic> data = {};

  TextEditingController _addressController = TextEditingController();
  TextEditingController _noteController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();


  LatLng _currentPosition = const LatLng(21.0285, 105.8542);

  @override
  void dispose() {
    // Giải phóng bộ nhớ khi thoát màn hình
    _dateController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }


  Widget _buildSmallButton(
      String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Future<void> _selectDateTime(BuildContext context) async {
    final DateTime now = DateTime.now();

    // Bước 1: Chọn Ngày
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C63FF), // Màu chủ đạo của bạn
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      // Bước 2: Chọn Giờ (nếu đã chọn ngày)
      if (!context.mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
      );

      if (pickedTime != null) {
        // Bước 3: Gộp Ngày và Giờ lại format thành chuỗi
        final DateTime finalDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() {
          _dateController.text = DateFormat('dd/MM/yyyy HH:mm').format(finalDateTime);
        });
      }
    }
  }

  Widget _buildFancyTextField(String label, IconData icon,TextEditingController controller,
      {String? hint, int maxLines = 1, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: TextFormField(
        controller: controller,
        onTap: onTap,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: const Color(0xFF6C63FF)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  void showDialogImage() {
    String status = data['status'];
    int potholeCount = data['potholeCount'];
    Uint8List imageBytes = data['imageBytes'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              status == 'red'
                  ? Icons.warning
                  : status == 'yellow'
                      ? Icons.warning_amber
                      : Icons.check_circle,
              color: status == 'red'
                  ? Colors.red
                  : status == 'yellow'
                      ? Colors.orange
                      : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(
              "Phát hiện: $potholeCount ổ gà",
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                imageBytes,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                getStatusText(status),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: getStatusColor(status),
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Nút Hủy
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text("Hủy"),
          ),
          // Nút Lưu kết quả
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx, imageBytes);
              await PotholeService()
                  .saveToFirebase(imageBytes, status, potholeCount, context);
            },
            child: const Text("Lưu kết quả"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text("Báo cáo sự cố", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 25),),
          centerTitle: true,
          backgroundColor: Color(0xFF6C63FF),
          foregroundColor: Colors.black),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upload Area Styling
            if (data['imageBytes'] == null)
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FE),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                        color: const Color(0xFF6C63FF).withOpacity(0.3),
                        width: 2,
                        style: BorderStyle.solid),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5))
                    ]),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.grey.withOpacity(0.2),
                                    blurRadius: 10)
                              ]),
                          child: const Icon(Icons.cloud_upload_rounded,
                              size: 40, color: Color(0xFF6C63FF)),
                        ),
                        const SizedBox(height: 5),
                        const Text("Chạm để tải ảnh lên",
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Positioned(
                      bottom: 10,
                      child: Row(
                        children: [
                          _buildSmallButton(
                              "Camera", Icons.camera_alt, Colors.blue,
                              () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                                source: ImageSource.camera);
                            if (img != null && context.mounted) {
                              data = await PotholeService()
                                  .processImage(img, context);
                              showDialogImage();
                            }
                          }),
                          const SizedBox(width: 15),
                          _buildSmallButton(
                              "Thư viện", Icons.photo_library, Colors.purple,
                              () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                                source: ImageSource.gallery);
                            if (img != null && context.mounted)
                              PotholeService().processImage(img, context);
                          }),
                        ],
                      ),
                    )
                  ],
                ),
              )
            else
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: Image.memory(
                  data['imageBytes'],
                  fit: BoxFit.fill,
                ),
                ),

            const SizedBox(height: 30),
            const Text("Thông tin chi tiết",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),

            _buildFancyTextField(
              "Ngày báo cáo",
              Icons.calendar_today_rounded,
              _dateController,
              onTap: () => _selectDateTime(context), // Mở lịch
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _buildFancyTextField(
                        "Địa chỉ", Icons.location_on_rounded, _addressController,
                        hint: "Nhập tuyến đường cụ thể...")),
                const SizedBox(width: 10),
                Container(
                  height: 55,
                  width: 55,
                  decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orange)),
                  child: IconButton(
                      onPressed: () {
                        showMapDialog();
                      },
                      icon: const Icon(Icons.map, color: Colors.orange)),
                )
              ],
            ),
            const SizedBox(height: 20),
            _buildFancyTextField("Ghi chú", Icons.note_alt_rounded, _noteController,
                maxLines: 3),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () async {
                  if(data.isNotEmpty){
                    String status = data['status'];
                    int potholeCount = data['potholeCount'];
                    Uint8List imageBytes = data['imageBytes'];
                    await PotholeService()
                        .saveToFirebase(imageBytes, status, potholeCount, context);
                  }
                  else{
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Vui lòng tải ảnh và nhập đầy đủ thông tin"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  elevation: 10,
                  shadowColor: const Color(0xFF6C63FF).withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("GỬI BÁO CÁO",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Hàm này dùng API Nominatim (giống phần search của bạn) để lấy địa chỉ từ LatLng
  Future<String> _getAddressFromLatLng(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'PoleHoleApp/1.0 (test@gmail.com)', // Giữ nguyên User-Agent của bạn
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] ?? "Không xác định được địa chỉ";
      }
    } catch (e) {
      log("Lỗi lấy địa chỉ: $e");
    }
    return "Lỗi kết nối";
  }

  void showMapDialog() {
    // Tạo controller riêng cho map trong dialog để tránh lỗi "Controller already attached"
    final MapController dialogMapController = MapController();

    // Biến tạm để lưu vị trí đang chọn trong dialog
    LatLng selectedPos = _currentPosition;
    String selectedAddress = "Đang tải vị trí...";

    // Lấy địa chỉ ban đầu
    _getAddressFromLatLng(selectedPos.latitude, selectedPos.longitude).then((value) {
      selectedAddress = value;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // Dùng StatefulBuilder để chỉ render lại BottomSheet khi chạm vào map
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateSheet) {
            return FractionallySizedBox(
              heightFactor: 0.75,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    // --- HIỂN THỊ ĐỊA CHỈ ĐÃ CHỌN ---
                    Text(
                      "Vị trí đang chọn:",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selectedAddress,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 15),

                    // --- BẢN ĐỒ ---
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FlutterMap(
                          mapController: dialogMapController, // Dùng controller riêng
                          options: MapOptions(
                            initialCenter: selectedPos,
                            initialZoom: 16.0,
                            // Tương tác
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                            ),
                            // --- SỰ KIỆN TAP ---
                            onTap: (tapPosition, point) async {
                              // 1. Cập nhật UI ngay lập tức để di chuyển Marker
                              setStateSheet(() {
                                selectedPos = point;
                                selectedAddress = "Đang lấy địa chỉ...";
                              });

                              // 2. Di chuyển Map đến vị trí mới
                              dialogMapController.move(point, dialogMapController.camera.zoom);

                              // 3. Gọi API lấy địa chỉ
                              String newAddress = await _getAddressFromLatLng(point.latitude, point.longitude);

                              // 4. Cập nhật lại text địa chỉ
                              if (context.mounted) {
                                setStateSheet(() {
                                  selectedAddress = newAddress;
                                });
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c'],
                              userAgentPackageName: 'com.example.polehole_app',
                            ),
                            MarkerLayer(
                              markers: [
                                // Marker tại vị trí ĐANG CHỌN (Màu Đỏ cho nổi bật)
                                Marker(
                                  point: selectedPos,
                                  width: 60,
                                  height: 60,
                                  child: const Icon(Icons.location_on, color: Colors.red, size: 50),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // --- NÚT XÁC NHẬN ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Khi nhấn xác nhận:
                          // 1. Cập nhật text ở ô tìm kiếm màn hình chính
                          setState(() {
                            _addressController.text = selectedAddress;
                            // Nếu muốn map chính cũng bay tới đó thì uncomment dòng dưới:
                            // _mapController.move(selectedPos, 16);
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text("Xác nhận vị trí này", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
