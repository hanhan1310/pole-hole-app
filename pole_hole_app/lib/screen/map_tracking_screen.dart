import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../service/api_service.dart';
import '../widget/funct.dart'; // Đổi lại đúng đường dẫn file service của bạn (PotholeService)
// import '../widget/funct.dart'; // Nếu bạn có file này thì giữ, ko thì bỏ qua

class MapTrackingScreen extends StatefulWidget {
  final Function(bool) onTrackingChanged;

  const MapTrackingScreen({super.key, required this.onTrackingChanged});

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Vị trí mặc định (Hà Nội)
  LatLng _currentPosition = const LatLng(21.0285, 105.8542);

  // Quản lý luồng vị trí
  StreamSubscription<Position>? _positionStreamSubscription;

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

  // Các biến cho Logic Tốc độ & Chụp ảnh
  LatLng? _lastPositionForSpeed;
  DateTime? _lastSpeedCalcTime;
  DateTime? _lastCaptureTime;
  bool _isPausedBySpeed = false;
  bool _isTooFast = false;

  final List<Map<String, dynamic>> _vehicleOptions = [
    {
      'name': 'Xe máy',
      'icon': Icons.two_wheeler,
      'color': Colors.blue,
      'speed': '25 - 35 km/h',
      'desc': 'Phù hợp di chuyển trong phố.',
      'isLocked': false, // Mở
    },
    {
      'name': 'Ô tô',
      'icon': Icons.directions_car,
      'color': Colors.orange,
      'speed': '30 - 45 km/h',
      'desc': 'Camera ổn định, ít rung lắc.',
      'isLocked': true, // <--- KHÓA
    },
    {
      'name': 'Xe đạp',
      'icon': Icons.directions_bike,
      'color': Colors.teal,
      'speed': '10 - 20 km/h',
      'desc': 'Di chuyển chậm, độ nét cao.',
      'isLocked': true, // <--- KHÓA
    },
    {
      'name': 'Đi bộ',
      'icon': Icons.directions_walk,
      'color': Colors.green,
      'speed': '< 10 km/h',
      'desc': 'Độ chính xác AI cao nhất.',
      'isLocked': false, // Mở
    },
  ];

  final Map<String, double> _vehicleSpeedLimits = {
    'Xe máy': 30.0, // Đã chỉnh lại cho hợp lý hơn (xe máy đi phố tầm 30-40)
    'Ô tô': 40.0,
    'Xe đạp': 15.0,
    'Đi bộ': 10.0, // Đi bộ thì ít khi quá nhanh
  };

  final PotholeService _potholeService = PotholeService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    _checkPermissionAndStartTracking();

    _subscribeToPotholes();
  }

  @override
  void dispose() {
    _assessmentsSub?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    _positionStreamSubscription?.cancel();
    _scanTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _checkPermissionAndStartTracking() async {
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vui lòng bật GPS')));
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Quyền vị trí bị từ chối')));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Quyền vị trí bị từ chối vĩnh viễn. Hãy mở cài đặt.')));
      return;
    }

    _startLiveLocationTracking();
  }

  void _startLiveLocationTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      if (_isTracking) {
        _mapController.move(_currentPosition, 17.0);
      }
    });
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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Không thể mở Camera. Hãy kiểm tra quyền truy cập!")));
        }
        return;
      }
    }
    setState(() {
      _isTracking = true;
      _currentSpeed = 0;
      _lastPositionForSpeed = _currentPosition;
      _lastSpeedCalcTime = DateTime.now();
      _lastCaptureTime = DateTime.now();
      _isPausedBySpeed = false;
      _isTooFast = false;
    });
    widget.onTrackingChanged(true);
    WakelockPlus.enable();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _calculateSpeedAndDecide();
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

  void _calculateSpeedAndDecide() {
    if (!_isTracking) return;
    final now = DateTime.now();
    if (_lastPositionForSpeed == null || _lastSpeedCalcTime == null) {
      _lastPositionForSpeed = _currentPosition;
      _lastSpeedCalcTime = now;
      return;
    }
    double distanceInMeters = Geolocator.distanceBetween(
      _lastPositionForSpeed!.latitude,
      _lastPositionForSpeed!.longitude,
      _currentPosition.latitude,
      _currentPosition.longitude,
    );
    double timeDiffSeconds = now.difference(_lastSpeedCalcTime!).inMilliseconds / 1000.0;
    if (timeDiffSeconds > 0) {
      double speedKmh = (distanceInMeters / timeDiffSeconds) * 3.6;
      if (speedKmh < 1.0 || distanceInMeters < 2.0) speedKmh = 0.0;
      setState(() {
        _currentSpeed = speedKmh;
        _lastPositionForSpeed = _currentPosition;
        _lastSpeedCalcTime = now;
      });
    }
    _checkCaptureCondition(now);
  }

  void _checkCaptureCondition(DateTime now) {
    double limit = _vehicleSpeedLimits[_selectedVehicle] ?? 30.0;
    if (_currentSpeed > limit) {
      if (!_isTooFast) {
        setState(() => _isTooFast = true);
      }
    } else {
      if (_isTooFast) setState(() => _isTooFast = false);
    }
    if (_currentSpeed < 5.0 && _selectedVehicle != 'Đi bộ') {
      if (!_isPausedBySpeed) {
        setState(() => _isPausedBySpeed = true);
      }
      return;
    } else {
      if (_isPausedBySpeed) {
        setState(() => _isPausedBySpeed = false);
      }
    }
    int intervalSeconds;
    if (_currentSpeed >= 15.0) {
      intervalSeconds = 5;
    } else {
      intervalSeconds = 7;
    }
    if (_isTooFast) intervalSeconds = 8;
    if (_lastCaptureTime == null ||
        now.difference(_lastCaptureTime!).inSeconds >= intervalSeconds) {
      log("📸 CHỤP ẢNH: Speed $_currentSpeed km/h - Interval ${intervalSeconds}s");
      _captureAndUpload();
      _lastCaptureTime = now;
    }
  }

  Future<void> _captureAndUpload() async {
    if (_isProcessingFrame || _cameraController == null || !_cameraController!.value.isInitialized)
      return;
    _isProcessingFrame = true;
    try {
      final XFile image = await _cameraController!.takePicture();
      double lat = _currentPosition.latitude;
      double lng = _currentPosition.longitude;
      String timeReport = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      String timeLog = DateFormat('HH:mm:ss').format(DateTime.now());
      log("📤 [$timeLog] Gửi ảnh lên server...");
      if (!mounted) return;
      var aiResult = await _potholeService.processImage(image, context);
      if (aiResult != null) {
        String status = aiResult['status'];
        int count = aiResult['potholeCount'];
        Uint8List imgBytes = aiResult['imageBytes'];
        log("✅ KẾT QUẢ: $status - $count ổ gà");
        await _potholeService.saveToFirebase(
          imgBytes, // 1. imageBytes
          status, // 2. status
          count, // 3. potholeCount
          "Tự động quét", // 4. addressStart (Text)
          "Tự động quét", // 5. addressEnd (Text)
          lat, // 6. startLat
          lng, // 7. startLng
          lat, // 8. endLat (Điểm quét là 1 điểm nên đầu=cuối)
          lng, // 9. endLng
          timeReport, // 10. dateReport
          "Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h ($_selectedVehicle)", // 11. note
          lat, // 12. lat (Tham số legacy)
          lng, // 13. lng (Tham số legacy)
          context, // 14. context
        );
      }
    } catch (e) {
      log("❌ Lỗi Scan: $e");
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: _isTracking ? Colors.red : Colors.grey, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      _isTracking ? "AI ĐANG QUÉT..." : "CHẾ ĐỘ CHỜ",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
    _assessmentsSub =
        FirebaseFirestore.instance.collection('polehole').snapshots().listen((snapshot) {
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

          LatLng startPoint;
          LatLng endPoint;

          if (data['start_coords'] != null && data['end_coords'] != null) {
            startPoint = LatLng(data['start_coords']['lat'], data['start_coords']['lng']);
            endPoint = LatLng(data['end_coords']['lat'], data['end_coords']['lng']);
          } else {
            double lat = data['latitude'] ?? 21.0285;
            double lng = data['longitude'] ?? 105.8542;
            startPoint = LatLng(lat, lng);
            endPoint = LatLng(lat, lng);
          }

          newMarkers.add(
            Marker(
              point: startPoint,
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () {
                  _showPotholeInfo(data);
                },
                child: Container(
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                  child: const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          );

          if (startPoint.latitude != endPoint.latitude ||
              startPoint.longitude != endPoint.longitude) {
            newPolylines.add(
              Polyline(
                points: [startPoint, endPoint],
                color: statusColor.withOpacity(0.7),
                strokeWidth: 6.0,
                borderStrokeWidth: 1.0,
                borderColor: Colors.white,
                strokeCap: StrokeCap.round,
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

  void _showPotholeInfo(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text("Chi tiết báo cáo",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                  children: [
                    const TextSpan(
                        text: "Người khảo sát: ", style: TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: 'Người dùng'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                  children: [
                    const TextSpan(
                        text: "Thời gian: ", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: formatDateTimeStamp(data['created_at'])),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                  children: [
                    const TextSpan(
                        text: "Bắt đầu: ", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: data['location_start'] ?? 'N/A'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                  children: [
                    const TextSpan(
                        text: "Kết thúc: ", style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: data['location_end'] ?? 'N/A'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (data['image'] != null)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      data['image'],
                      fit: BoxFit.contain,
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showVehicleBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.8, // Tăng chiều cao lên chút để chứa đủ thông tin
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thanh kéo (Handle)
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const Text(
                  "Chọn phương tiện",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  "Chọn đúng phương tiện giúp AI đưa ra đánh giá tốc độ và nhận diện ổ gà chuẩn xác nhất.",
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // 2 cột
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                      childAspectRatio: 0.75, // Tỉ lệ khung hình (Cao hơn để chứa nhiều text)
                    ),
                    itemCount: _vehicleOptions.length,
                    itemBuilder: (context, index) {
                      final item = _vehicleOptions[index];
                      return _buildDetailedVehicleCard(item);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailedVehicleCard(Map<String, dynamic> item) {
    bool isSelected = _selectedVehicle == item['name'];
    bool isLocked = item['isLocked'] == true;
    Color themeColor = item['color'];

    return GestureDetector(
      onTap: isLocked
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Tính năng này đang phát triển!"),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          : () {
              setState(() {
                _selectedVehicle = item['name'];
                _selectedVehicleIcon = item['icon'];
              });
              Navigator.pop(context);
            },
      child: Opacity(
        opacity: isLocked ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: isLocked
                ? Colors.grey[100]
                : (isSelected ? themeColor.withOpacity(0.05) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLocked
                  ? Colors.grey.shade300
                  : (isSelected ? themeColor : Colors.grey.shade200),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [
              if (!isSelected && !isLocked)
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
            ],
          ),
          child: Stack(
            children: [
              // Nội dung chính
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLocked ? Colors.grey[300] : themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child:
                          Icon(item['icon'], color: isLocked ? Colors.grey : themeColor, size: 32),
                    ),
                    const Spacer(),
                    Text(
                      item['name'],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isLocked ? Colors.grey : (isSelected ? themeColor : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item['desc'],
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    // Badge Tốc độ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed, size: 14, color: Colors.grey),
                          const SizedBox(width: 5),
                          Text(
                            item['speed'],
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),

              // Icon Checkmark khi được chọn
              if (isSelected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),

              if (isLocked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Icon(Icons.lock_outline_rounded, size: 40, color: Colors.grey),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.0,
              minZoom: 14.0,
              maxZoom: 17.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(8.18, 102.14),
                  const LatLng(23.39, 109.46),
                ),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.polehole_app',
                tileProvider: CancellableNetworkTileProvider(),
              ),
              PolylineLayer(
                polylines: [..._roadPolylines],
              ),
              MarkerLayer(
                markers: [
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
                              color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3)),
                        ),
                      ],
                    ),
                  ),
                  ..._potholeMarkers,
                ],
              ),
            ],
          ),

          Positioned(
            bottom: 220,
            right: 20,
            child: GestureDetector(
              onTap: () {
                _mapController.move(_currentPosition, _mapController.camera.zoom);
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
                ),
                child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 24),
              ),
            ),
          ),

          if (_isCameraInitialized)
            Positioned(
              top: 0,
              left: 0,
              width: 1,
              height: 1,
              child: CameraPreview(_cameraController!),
            ),

          if (_isTracking && _isTooFast)
            Positioned(
              top: 100, // Dưới thanh tốc độ một chút
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Bạn đi quá nhanh! ($_currentSpeed km/h)\nHãy giảm tốc để AI nhận diện chuẩn.",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isTracking && _isPausedBySpeed && !_isTooFast)
            Positioned(
              top: 160,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.pause_circle_filled, color: Colors.white, size: 20),
                    SizedBox(width: 5),
                    Text("Tạm dừng chụp (Xe đi chậm)",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          if (_isTracking)
            Positioned(
              top: 60,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: const Color(0xFF6C63FF), width: 2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 15)
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
                          color: Colors.black87, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 5),
                      child: Text("km/h",
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          if (_isTracking)
            Positioned(
              top: 120,
              right: 20,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {/* Hàm show chú thích cũ của bạn */},
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
                      child: const Icon(Icons.info_outline, color: Colors.blueGrey),
                    ),
                  ),
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: _showCameraMonitor,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)]),
                      child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          if (!_isTracking)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5))
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: "Tìm đường (VD: Giải Phóng, Hà Nội)...",
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6C63FF)),
                        // Nút xóa text
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _suggestions = []);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty || _isLoadingSuggestions)
                    if (_suggestions.isNotEmpty || _isLoadingSuggestions)
                      Container(
                        margin: const EdgeInsets.only(top: 5, left: 10, right: 10),
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                        ),
                        constraints: const BoxConstraints(maxHeight: 250), // Giới hạn chiều cao
                        child: _isLoadingSuggestions
                            ? const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _suggestions.length,
                                separatorBuilder: (ctx, i) =>
                                    const Divider(height: 1, indent: 15, endIndent: 15),
                                itemBuilder: (context, index) {
                                  final item = _suggestions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_on_outlined,
                                        color: Colors.grey, size: 20),
                                    title: Text(
                                      item.displayName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    onTap: () => _selectLocation(item), // <--- CHỌN ĐỊA ĐIỂM
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8B85FF)]),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(_selectedVehicleIcon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(_selectedVehicle,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 160,
            right: 20,
            child: GestureDetector(
              onTap: () {
                showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                          title: const Text("Chú thích bản đồ"),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildLegendRow(Colors.red, "Đường xấu (Nhiều ổ gà)"),
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
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
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
                  boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 20)],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 15),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("HỆ THỐNG ĐANG CHẠY",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        Text("Camera đang phân tích ngầm...",
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _stopAutoScan,
                      icon:
                          const Icon(Icons.stop_circle_outlined, size: 40, color: Colors.redAccent),
                    )
                  ],
                ),
              ),
            ),

          // Nút BẮT ĐẦU QUÉT
          if (_isTracking == false)
            Positioned(
              bottom: 100,
              left: 0,
              right: 120,
              child: Center(
                child: ScaleTransition(
                  scale: _pulseController,
                  child: FloatingActionButton.extended(
                    onPressed: _startAutoScan,
                    elevation: 20,
                    backgroundColor: const Color(0xFF6C63FF),
                    icon: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
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

  SearchResult({required this.displayName, required this.lat, required this.lon});
}
