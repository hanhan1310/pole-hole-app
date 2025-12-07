import 'dart:async';
import 'dart:developer';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // Thư viện Map
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart'; // Xử lý tọa độ
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapTrackingScreen extends StatefulWidget {
  final Function(bool) onTrackingChanged;

  const MapTrackingScreen({super.key, required this.onTrackingChanged});

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(21.0285, 105.8542);
  List<Marker> _potholeMarkers = [];
  StreamSubscription? _assessmentsSub;

  bool _isTracking = false;
  double _currentSpeed = 0.0;
  IconData _selectedVehicleIcon = Icons.two_wheeler;
  String _selectedVehicle = 'Xe máy';
  late AnimationController _pulseController;
  CameraController? _cameraController;
  Timer? _scanTimer;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  final TextEditingController _searchController = TextEditingController();
  List<SearchResult> _suggestions = [];
  Timer? _debounce;
  bool _isLoadingSuggestions = false;
  List<Polyline> _roadPolylines = [];
  List<Polyline> _dummyPolylines = [];
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    _getCurrentLocation();
    _loadDummyPolylines();
    _subscribeToPotholes();
  }

  void _loadDummyPolylines() {
    setState(() {
      _dummyPolylines = [
        Polyline(
          points: [
            const LatLng(21.002617, 105.8065661),
            const LatLng(21.002169, 105.809195),
            const LatLng(21.002276, 105.810549),
          ],
          color: Colors.red.withOpacity(0.8),
          strokeWidth: 8.0,
          borderStrokeWidth: 2.0,
          borderColor: Colors.white,
        ),
        Polyline(
          points: [
            const LatLng(21.027000, 105.852000),
            const LatLng(21.026000, 105.851000),
          ],
          color: Colors.green.withOpacity(0.8),
          strokeWidth: 8.0,
          borderStrokeWidth: 2.0,
          borderColor: Colors.white,
        ),
        Polyline(
          points: [
            const LatLng(21.025000, 105.855000),
            const LatLng(21.025000, 105.858000),
          ],
          color: Colors.orange.withOpacity(0.8),
          strokeWidth: 8.0,
          borderStrokeWidth: 2.0,
          borderColor: Colors.white,
        ),
      ];
    });
  }

  @override
  void dispose() {
    _assessmentsSub?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  void _startAutoScan() async {
    if (!_isCameraInitialized) {
      await _initCamera();

      if (!_isCameraInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text("Không thể mở Camera. Hãy kiểm tra quyền truy cập!")));
        }
        return;
      }
    }
    setState(() {
      _isTracking = true;
      _currentSpeed = 0;
    });
    widget.onTrackingChanged(true);
    log(_isTracking.toString());
    WakelockPlus.enable();
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _captureAndUpload();
    });
  }

  void _stopAutoScan() {
    _scanTimer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _isTracking = false;
      _currentSpeed = 0.0;
    });
    widget.onTrackingChanged(false);
  }

  Future<void> _captureAndUpload() async {
    if (_isProcessingFrame || _cameraController == null) return;

    _isProcessingFrame = true;

    try {
      final XFile image = await _cameraController!.takePicture();

      double lat = _currentPosition.latitude;
      double lng = _currentPosition.longitude;

      final bytes = await image.readAsBytes();
    } catch (e) {
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _showCameraMonitor() {
    if (!_isCameraInitialized || _cameraController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera chưa sẵn sàng!")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1 / _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
              ),
            ),
            Positioned(
              top: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: _isTracking ? Colors.red : Colors.grey,
                        size: 14),
                    const SizedBox(width: 8),
                    Text(
                      _isTracking ? "AI ĐANG QUÉT..." : "CHẾ ĐỘ CHỜ",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check quyền (Giả sử đã check ở màn Splash/Permission rồi)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentPosition, 15.0);
    } catch (e) {}
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        _fetchSuggestions(query);
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isLoadingSuggestions = true);
    try {
      double delta = 0.5;
      String viewbox = '';

      if (_currentPosition.latitude != 0 && _currentPosition.longitude != 0) {
        double left = _currentPosition.longitude - delta;
        double top = _currentPosition.latitude + delta;
        double right = _currentPosition.longitude + delta;
        double bottom = _currentPosition.latitude - delta;
        viewbox = '$left,$top,$right,$bottom';
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'addressdetails': '1',
        'countrycodes': 'vn',
        if (viewbox.isNotEmpty) 'viewbox': viewbox,
        if (viewbox.isNotEmpty) 'bounded': '0',
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'PoleHoleApp/1.0 (test@gmail.com)',
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _suggestions = data
              .map((item) => SearchResult(
                    displayName: item['display_name'],
                    lat: double.parse(item['lat']),
                    lon: double.parse(item['lon']),
                  ))
              .toList();
        });
      }
    } catch (e) {
    } finally {
      setState(() => _isLoadingSuggestions = false);
    }
  }

  void _selectLocation(SearchResult result) {
    setState(() {
      _suggestions = [];
      _searchController.text = result.displayName;
      FocusScope.of(context).unfocus();
    });

    _mapController.move(LatLng(result.lat, result.lon), 16.0);
  }

  void _subscribeToPotholes() {
    _assessmentsSub = FirebaseFirestore.instance
        .collection('client')
        .snapshots()
        .listen((snapshot) {
      final List<Marker> newMarkers = [];
      final List<Polyline> newPolylines = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        try {
          Map<String, dynamic> status = data['status'] ?? {};
          int code = status['code'] ?? 1;

          Color statusColor;
          if (code == 3)
            statusColor = Colors.red;
          else if (code == 2)
            statusColor = Colors.orange;
          else
            statusColor = Colors.green;

          String startStr = data['location_start'] ?? "0,0";
          List<String> startParts = startStr.split(',');
          LatLng startPoint = LatLng(double.parse(startParts[0].trim()),
              double.parse(startParts[1].trim()));

          String endStr = data['location_end'] ?? startStr;
          List<String> endParts = endStr.split(',');
          LatLng endPoint = LatLng(double.parse(endParts[0].trim()),
              double.parse(endParts[1].trim()));

          newMarkers.add(
            Marker(
              point: startPoint,
              width: 30,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4)
                    ]),
                child:
                    Icon(Icons.warning_rounded, color: Colors.white, size: 18),
              ),
            ),
          );

          if (startPoint != endPoint) {
            newPolylines.add(
              Polyline(
                points: [startPoint, endPoint],
                color: statusColor.withOpacity(0.7),
                strokeWidth: 6.0,
                borderStrokeWidth: 1.0,
                borderColor: Colors.white,
              ),
            );
          }
        } catch (e) {
          continue;
        }
      }

      setState(() {
        _potholeMarkers = newMarkers;
        _roadPolylines = newPolylines;
      });
    });
  }

  void _showVehicleBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 25),
                const Text("Chọn phương tiện",
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Text("Lựa chọn phương tiện để tối ưu hóa thuật toán AI",
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 30),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    children: [
                      _buildVehicleCard(
                          "Xe máy", Icons.two_wheeler, Colors.blue),
                      _buildVehicleCard(
                          "Ô tô", Icons.directions_car, Colors.orange),
                      _buildVehicleCard(
                          "Đi bộ", Icons.directions_walk, Colors.green),
                      _buildVehicleCard(
                          "Xe đạp", Icons.directions_bike, Colors.teal),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleCard(String name, IconData icon, Color color) {
    bool isSelected = _selectedVehicle == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = name;
          _selectedVehicleIcon = icon;
        });
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? color : Colors.grey.shade200,
              width: isSelected ? 3 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 10),
            Text(name,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: ScaleTransition(
        scale: _pulseController,
        child: FloatingActionButton.extended(
          onPressed: () {
            _startAutoScan();
          },
          elevation: 20,
          backgroundColor: const Color(0xFF6C63FF),
          icon: const Icon(Icons.play_arrow_rounded,
              size: 30, color: Colors.white),
          label: const Text("BẮT ĐẦU QUÉT",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.white)),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition, // Vị trí khởi tạo
              initialZoom: 15.0,
              minZoom: 14.0,
              maxZoom: 17.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(8.18, 102.14), // Góc dưới trái VN
                  const LatLng(23.39, 109.46), // Góc trên phải VN
                ),
              ),
              interactionOptions: const InteractionOptions(
                // Tắt xoay map (rotate) giúp map mượt hơn nhiều, chỉ cho phép zoom/pan
                flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
              ),
            ),
            children: [
              // Lớp nền bản đồ (OpenStreetMap)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const [
                  'a',
                  'b',
                  'c'
                ], // Tải song song giúp nhanh gấp 3 lần
                userAgentPackageName:
                    'com.example.polehole_app', // Thay bằng package id của bạn
                tileProvider: CancellableNetworkTileProvider(),
              ),

              PolylineLayer(
                polylines: [..._dummyPolylines, ..._roadPolylines],
              ),

              // Lớp Marker (Các điểm ổ gà từ Firebase)
              MarkerLayer(
                markers: [
                  // Marker vị trí hiện tại của tôi (Màu xanh dương có hiệu ứng tỏa)
                  Marker(
                    point: _currentPosition,
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 3)),
                        ),
                      ],
                    ),
                  ),
                  // Marker danh sách ổ gà
                  ..._potholeMarkers,
                ],
              ),
            ],
          ),

          if (_isCameraInitialized)
            Positioned(
              top: 0,
              left: 0,
              width: 1,
              height: 1,
              child: CameraPreview(_cameraController!),
            ),
          // 2. LAYER GIAO DIỆN (Giữ nguyên thiết kế đẹp của bạn)

          if (_isTracking)
            Positioned(
              top: 60,
              left: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: const Color(0xFF6C63FF), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.3),
                        blurRadius: 15)
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(Icons.speed, color: Colors.redAccent, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      "${_currentSpeed.toStringAsFixed(1)}",
                      style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 32,
                          fontWeight: FontWeight.w900),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 5),
                      child: Text("km/h",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          if (_isTracking)
            Positioned(
              top: 120, // Đặt cùng hàng với nút Info hoặc chỉnh tùy ý
              right: 20,
              child: Column(
                // Dùng Column để xếp dọc các nút bên phải
                children: [
                  // Nút Info cũ (nếu bạn muốn giữ)
                  GestureDetector(
                    onTap: () {/* Hàm show chú thích cũ của bạn */},
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 5)
                          ]),
                      child: const Icon(Icons.info_outline,
                          color: Colors.blueGrey),
                    ),
                  ),

                  const SizedBox(height: 15), // Khoảng cách

                  // --- NÚT MỚI: SOI CAMERA ---
                  GestureDetector(
                    onTap: _showCameraMonitor, // <--- GỌI HÀM VỪA TẠO
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.black87, // Màu đen cho ngầu
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 5)
                          ]),
                      child: const Icon(Icons.camera_alt_outlined,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
// B. Thanh tìm kiếm thông minh (Autocomplete)
          if (!_isTracking)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  // 1. Ô nhập liệu
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30), // Bo tròn
                      // Nếu đang có gợi ý thì bỏ bo góc dưới để nối liền với list
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5))
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged, // <--- GỌI HÀM KHI GÕ
                      decoration: InputDecoration(
                        hintText: "Tìm đường (VD: Giải Phóng, Hà Nội)...",
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon:
                            const Icon(Icons.search, color: Color(0xFF6C63FF)),
                        // Nút xóa text
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _suggestions = []);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),

                  // 2. Danh sách gợi ý (Chỉ hiện khi có dữ liệu)
                  if (_suggestions.isNotEmpty || _isLoadingSuggestions)
                    Container(
                      margin:
                          const EdgeInsets.only(top: 5, left: 10, right: 10),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 10)
                        ],
                      ),
                      constraints: const BoxConstraints(
                          maxHeight: 250), // Giới hạn chiều cao
                      child: _isLoadingSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _suggestions.length,
                              separatorBuilder: (ctx, i) => const Divider(
                                  height: 1, indent: 15, endIndent: 15),
                              itemBuilder: (context, index) {
                                final item = _suggestions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: Colors.grey,
                                      size: 20),
                                  title: Text(
                                    item.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  onTap: () => _selectLocation(
                                      item), // <--- CHỌN ĐỊA ĐIỂM
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
          // Nút Chọn Phương Tiện (Góc trên phải)
          if (!_isTracking)
            Positioned(
              bottom: 100,
              right: 20,
              child: GestureDetector(
                onTap: _showVehicleBottomSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF8B85FF)]),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(_selectedVehicleIcon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(_selectedVehicle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),

          // Nút Chú thích (Mới thêm - Dưới nút chọn xe)
          Positioned(
            bottom: 160,
            right: 20,
            child: GestureDetector(
              onTap: () {
                // Hiển thị chú thích màu
                showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                          title: const Text("Chú thích bản đồ"),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildLegendRow(
                                  Colors.red, "Đường xấu (Nhiều ổ gà)"),
                              _buildLegendRow(Colors.orange, "Cần chú ý"),
                              _buildLegendRow(Colors.green, "Đường tốt"),
                              const Divider(),
                              _buildLegendRow(Colors.blue, "Vị trí của bạn"),
                            ],
                          ),
                        ));
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 5)
                    ]),
                child: const Icon(Icons.info_outline, color: Colors.blueGrey),
              ),
            ),
          ),

          // Panel trạng thái khi đang chạy
          if (_isTracking)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.redAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.redAccent.withOpacity(0.3),
                        blurRadius: 20)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.fiber_manual_record,
                          color: Colors.redAccent),
                    ),
                    const SizedBox(width: 15),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("HỆ THỐNG ĐANG CHẠY",
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                        Text("Camera đang phân tích ngầm...",
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _stopAutoScan,
                      icon: const Icon(Icons.stop_circle_outlined,
                          size: 40, color: Colors.redAccent),
                    )
                  ],
                ),
              ),
            ),

          // Nút BẮT ĐẦU QUÉT
          if (_isTracking == false)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: ScaleTransition(
                  scale: _pulseController,
                  child: FloatingActionButton.extended(
                    onPressed: _startAutoScan,
                    elevation: 20,
                    backgroundColor: const Color(0xFF6C63FF),
                    icon: const Icon(Icons.play_arrow_rounded,
                        size: 30, color: Colors.white),
                    label: const Text("BẮT ĐẦU QUÉT",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendRow(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    );
  }
}

// Class để lưu kết quả tìm kiếm gọn gàng
class SearchResult {
  final String displayName;
  final double lat;
  final double lon;

  SearchResult(
      {required this.displayName, required this.lat, required this.lon});
}
