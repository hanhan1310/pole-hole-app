import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../service/api_service.dart';

class UpdateRoadDataScreen extends StatefulWidget {
  const UpdateRoadDataScreen({super.key});

  @override
  State<UpdateRoadDataScreen> createState() => _UpdateRoadDataScreenState();
}

class _UpdateRoadDataScreenState extends State<UpdateRoadDataScreen> {
  Map<String, dynamic> data = {};

  final TextEditingController _addressStartController = TextEditingController();
  final TextEditingController _addressEndController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  // Tọa độ đã chọn
  LatLng? _startPosCoords;
  LatLng? _endPosCoords;

  // Biến kiểm soát việc cho phép sửa text
  bool _isStartEditable = false;
  bool _isEndEditable = false;

  String? _selectedStatus = 'green';
  final List<Map<String, dynamic>> _statusOptions = [
    {
      'value': 'green',
      'label': 'Tốt - Đường ổn định',
      'color': Colors.green,
      'icon': Icons.check_circle
    },
    {
      'value': 'yellow',
      'label': 'Cảnh báo - Có ít ổ gà',
      'color': Colors.orange,
      'icon': Icons.warning_amber
    },
    {
      'value': 'red',
      'label': 'Nguy hiểm - Nhiều ổ gà',
      'color': Colors.red,
      'icon': Icons.report_problem
    },
  ];

  LatLng _currentPosition = const LatLng(21.0285, 105.8542);

  @override
  void dispose() {
    _dateController.dispose();
    _addressStartController.dispose();
    _addressEndController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _fillCurrentLocation() async {
    try {
      // Kiểm tra quyền (Nếu chưa có thì xin, đoạn này nên làm kỹ hơn ở main, nhưng làm nhanh thì check ở đây)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // Lấy tọa độ GPS
      Position position =
          await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng currentPos = LatLng(position.latitude, position.longitude);

      // Lấy địa chỉ từ API
      String address = await _getAddressFromLatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          // Gán tọa độ
          _startPosCoords = currentPos;
          _endPosCoords = currentPos;

          // Gán địa chỉ văn bản
          _addressStartController.text = address;
          _addressEndController.text = address;

          // MỞ KHÓA CHO PHÉP SỬA
          _isStartEditable = true;
          _isEndEditable = true;
        });
      }
    } catch (e) {
      log("Lỗi lấy vị trí hiện tại: $e");
    }
  }

  Future<void> _openMapPicker(bool isStart) async {
    LatLng initialPos = isStart
        ? (_startPosCoords ?? const LatLng(21.0285, 105.8542))
        : (_endPosCoords ?? const LatLng(21.0285, 105.8542));

    final LocationResult? result = await showGeneralDialog<LocationResult>(
      context: context,
      pageBuilder: (ctx, a1, a2) => MapPickerDialog(initialPosition: initialPos),
      transitionBuilder: (ctx, a1, a2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a1),
          child: child,
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isStart) {
          _startPosCoords = result.latLng;
          _addressStartController.text = result.address;
          _isStartEditable = true;
        } else {
          _endPosCoords = result.latLng;
          _addressEndController.text = result.address;
          _isEndEditable = true;
        }
      });
    }
  }

  Widget _buildLocationInput({
    required String label,
    required TextEditingController controller,
    required bool isEditable,
    required LatLng? coords,
    required VoidCallback onMapPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onMapPressed,
              child: Container(
                height: 55,
                width: 55,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFF6C63FF)),
                ),
                child: const Icon(Icons.map_rounded, color: Color(0xFF6C63FF), size: 30),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 55,
                decoration: BoxDecoration(
                  color: isEditable ? Colors.white : Colors.grey[100],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: controller,
                  readOnly: !isEditable,
                  decoration: InputDecoration(
                    hintText: isEditable ? "Có thể chỉnh sửa địa chỉ..." : "Chọn bản đồ trước",
                    labelText: label,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    suffixIcon:
                        isEditable ? const Icon(Icons.edit, size: 16, color: Colors.grey) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (coords != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 65),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed, size: 14, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    "GPS: ${coords.latitude.toStringAsFixed(6)}, ${coords.longitude.toStringAsFixed(6)}",
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Future<void> _selectDateTime(BuildContext context) async {
    final DateTime now = DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C63FF),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      if (!context.mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
      );

      if (pickedTime != null) {
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

  Widget _buildFancyTextField(String label, IconData icon, TextEditingController controller,
      {String? hint, int maxLines = 1, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: TextFormField(
        onTapOutside: (ct) {
          FocusScope.of(context).unfocus();
        },
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
            "Báo cáo sự cố",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 25),
          ),
          centerTitle: true,
          backgroundColor: Color(0xFF6C63FF),
          foregroundColor: Colors.black),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                                BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10)
                              ]),
                          child: const Icon(Icons.cloud_upload_rounded,
                              size: 40, color: Color(0xFF6C63FF)),
                        ),
                        const SizedBox(height: 5),
                        const Text("Chạm để tải ảnh lên",
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Positioned(
                      bottom: 10,
                      child: Row(
                        children: [
                          _buildSmallButton("Camera", Icons.camera_alt, Colors.blue, () async {
                            final picker = ImagePicker();
                            final XFile? img = await picker.pickImage(
                                source: ImageSource.camera, imageQuality: 50, maxWidth: 1024);

                            if (img != null && context.mounted) {
                              _fillCurrentLocation();
                              try {
                                dynamic response =
                                    await PotholeService().processImage(img, context);
                                if (response != null) {
                                  setState(() {
                                    data = response;
                                    _selectedStatus = response['status'];
                                  });
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.error, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            e.toString(),
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 3),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          }),
                          const SizedBox(width: 15),
                          _buildSmallButton("Thư viện", Icons.photo_library, Colors.purple,
                              () async {
                            final picker = ImagePicker();
                            final XFile? img = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 50,
                              maxWidth: 1024,
                            );
                            if (img != null && context.mounted) {
                              try {
                                dynamic response =
                                    await PotholeService().processImage(img, context);
                                if (response == null) return;
                                log(response.toString());
                                setState(() {
                                  data = response;
                                  _selectedStatus = response['status'];
                                });
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.error, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            e.toString(),
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 3),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
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
                  color: Colors.grey[200],
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        data['imageBytes'],
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                data['imageBytes'] = null;
                              });
                              print("Đã nhấn nút xóa ảnh");
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 30),
            const Text("Xác nhận thông tin địa điểm",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _buildFancyTextField(
              "Ngày báo cáo",
              Icons.calendar_today_rounded,
              _dateController,
              onTap: () => _selectDateTime(context),
            ),
            const SizedBox(height: 20),
            _buildLocationInput(
              label: "Địa điểm bắt đầu",
              controller: _addressStartController,
              isEditable: _isStartEditable,
              coords: _startPosCoords,
              onMapPressed: () => _openMapPicker(true),
            ),
            const SizedBox(height: 20),
            _buildLocationInput(
              label: "Địa điểm kết thúc",
              controller: _addressEndController,
              isEditable: _isEndEditable,
              coords: _endPosCoords,
              onMapPressed: () => _openMapPicker(false),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5))
                ],
                border: Border.all(color: Colors.grey.shade300), // Viền nhẹ
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: "Trạng thái mặt đường",
                  prefixIcon: Icon(Icons.traffic, color: Color(0xFF6C63FF)), // Icon bên trái
                  border: InputBorder.none, // Bỏ viền mặc định của Input để dùng viền Container
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                icon: const Icon(Icons.arrow_drop_down_circle, color: Color(0xFF6C63FF)),
                items: _statusOptions.map((item) {
                  return DropdownMenuItem<String>(
                    value: item['value'],
                    child: Row(
                      children: [
                        // Dấu chấm tròn màu hoặc Icon thể hiện trạng thái
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: item['color'].withOpacity(0.1), // Nền nhạt
                            shape: BoxShape.circle,
                          ),
                          child: Icon(item['icon'], color: item['color'], size: 20),
                        ),
                        const SizedBox(width: 10),
                        // Text hiển thị
                        Text(
                          item['label'],
                          style: TextStyle(
                            color: item['color'], // Chữ cùng màu với trạng thái
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            _buildFancyTextField("Ghi chú", Icons.note_alt_rounded, _noteController, maxLines: 3),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () async {
                  if (data['imageBytes'] == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Vui lòng tải ảnh lên!"), backgroundColor: Colors.red));
                    return;
                  }
                  if (_startPosCoords == null || _endPosCoords == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Vui lòng chọn vị trí trên bản đồ!"),
                        backgroundColor: Colors.red));
                    return;
                  }
                  String finalStatus = _selectedStatus ?? data['status'] ?? 'green';
                  int count = data['potholeCount'] ?? 0;
                  String finalDate = _dateController.text.isEmpty
                      ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())
                      : _dateController.text;
                  await PotholeService().saveToFirebase(
                    data['imageBytes'],
                    finalStatus,
                    count,
                    _addressStartController.text,
                    _addressEndController.text,
                    _startPosCoords!.latitude,
                    _startPosCoords!.longitude,
                    _endPosCoords!.latitude,
                    _endPosCoords!.longitude,
                    finalDate,
                    _noteController.text,
                    _startPosCoords!.latitude,
                    _startPosCoords!.longitude,
                    context,
                  );

                  if (context.mounted) _resetForm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("GỬI BÁO CÁO",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

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
        'User-Agent': 'PoleHoleApp/1.0 (test@gmail.com)',
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

  void _resetForm() {
    setState(() {
      data = {};
      _addressStartController.clear();
      _addressEndController.clear();
      _noteController.clear();
      _dateController.clear();
      _startPosCoords = null;
      _endPosCoords = null;
      _isStartEditable = false;
      _isEndEditable = false;
      _selectedStatus = 'green';
    });
  }

  void showMapDialog(TextEditingController addressController, Function(LatLng) onConfirm) {
    final MapController dialogMapController = MapController();

    LatLng selectedPos = _currentPosition;
    String selectedAddress = "Đang tải vị trí...";

    _getAddressFromLatLng(selectedPos.latitude, selectedPos.longitude).then((value) {
      selectedAddress = value;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
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
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FlutterMap(
                          mapController: dialogMapController,
                          options: MapOptions(
                            initialCenter: selectedPos,
                            initialZoom: 16.0,
                            onTap: (tapPosition, point) async {
                              setStateSheet(() {
                                selectedPos = point; // Cập nhật vị trí marker
                                selectedAddress = "Đang lấy địa chỉ...";
                              });
                              dialogMapController.move(point, dialogMapController.camera.zoom);

                              String newAddress =
                                  await _getAddressFromLatLng(point.latitude, point.longitude);
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          addressController.text = selectedAddress;

                          onConfirm(selectedPos);

                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text("Xác nhận vị trí này",
                            style: TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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

class LocationResult {
  final LatLng latLng;
  final String address;
  LocationResult(this.latLng, this.address);
}

class MapPickerDialog extends StatefulWidget {
  final LatLng initialPosition;
  const MapPickerDialog({super.key, required this.initialPosition});

  @override
  State<MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<MapPickerDialog> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  late LatLng _selectedPos;
  String _selectedAddress = "Đang tải vị trí...";
  List<dynamic> _suggestions = [];
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedPos = widget.initialPosition;
    _getAddressFromLatLng(_selectedPos.latitude, _selectedPos.longitude);
  }

  // Hàm lấy địa chỉ từ tọa độ
  Future<void> _getAddressFromLatLng(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http.get(uri, headers: {'User-Agent': 'PoleHoleApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _selectedAddress = data['display_name']);
      }
    } catch (_) {
      if (mounted) setState(() => _selectedAddress = "Lỗi kết nối");
    }
  }

  // Hàm tìm kiếm địa chỉ
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() => _suggestions = []);
        return;
      }
      setState(() => _isLoading = true);
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': query,
          'format': 'json',
          'limit': '5',
          'addressdetails': '1',
          'countrycodes': 'vn',
        });
        final response = await http.get(uri, headers: {'User-Agent': 'PoleHoleApp/1.0'});
        if (response.statusCode == 200) {
          setState(() => _suggestions = json.decode(response.body));
        }
      } finally {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Tránh bàn phím đẩy map
      body: Stack(
        children: [
          // 1. BẢN ĐỒ
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPos,
              initialZoom: 16.0,
              onTap: (_, point) {
                setState(() {
                  _selectedPos = point;
                  _selectedAddress = "Đang lấy dữ liệu...";
                  _suggestions = [];
                  FocusScope.of(context).unfocus();
                });
                _getAddressFromLatLng(point.latitude, point.longitude);
              },
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              MarkerLayer(markers: [
                Marker(
                  point: _selectedPos,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 50),
                ),
              ]),
            ],
          ),

          Positioned(
            top: 40,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "Tìm kiếm vị trí...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _suggestions = []);
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    decoration:
                        BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      itemBuilder: (ctx, i) {
                        final item = _suggestions[i];
                        return ListTile(
                          title: Text(item['display_name']),
                          leading: const Icon(Icons.location_city, color: Colors.grey),
                          onTap: () {
                            final lat = double.parse(item['lat']);
                            final lon = double.parse(item['lon']);
                            final p = LatLng(lat, lon);
                            setState(() {
                              _selectedPos = p;
                              _selectedAddress = item['display_name'];
                              _suggestions = [];
                              _searchController.text = "";
                            });
                            _mapController.move(p, 16);
                            FocusScope.of(context).unfocus();
                          },
                        );
                      },
                    ),
                  )
              ],
            ),
          ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Vị trí: $_selectedAddress",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // NÚT HỦY (X) - Màu xám
                      InkWell(
                        onTap: () {
                          // Trả về null để không cập nhật gì cả
                          Navigator.pop(context, null);
                        },
                        child: Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(
                            color: Colors.grey[200], // Nền xám nhạt
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.close, color: Colors.black54),
                        ),
                      ),

                      const SizedBox(width: 10), // Khoảng cách

                      // NÚT XÁC NHẬN - Màu chính (Expanded để chiếm phần còn lại)
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.pop(
                                  context, LocationResult(_selectedPos, _selectedAddress));
                            },
                            child: const Text("XÁC NHẬN",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
