import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:pole_hole_app/widget/show_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model/report_model.dart';
import '../service/api_service.dart';
import 'detail_report_screen.dart'; // Đổi lại đúng đường dẫn file service của bạn (PotholeService)
// import '../widget/funct.dart'; // Nếu bạn có file này thì giữ, ko thì bỏ qua

class MapTrackingScreen extends StatefulWidget {
  final Function(bool) onTrackingChanged;

  const MapTrackingScreen({super.key, required this.onTrackingChanged});

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> with TickerProviderStateMixin {
  final User? _user = FirebaseAuth.instance.currentUser;

  final MapController _mapController = MapController();

  // Vị trí mặc định (Hà Nội)
  LatLng _currentPosition = const LatLng(21.0285, 105.8542);
  bool _hasFocusedOnce = false;

  // Quản lý luồng vị trí
  StreamSubscription<Position>? _positionStreamSubscription;
  List<Map<String, dynamic>> _cachedPotholes = [];

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

  DateTime? _lastCaptureTime;
  bool _isPausedBySpeed = false;
  bool _isTooFast = false;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  StreamSubscription? _onlineUsersSub;
  List<Marker> _onlineUserMarkers = [];
  final String _currentDeviceId = const Uuid().v4();
  String? _serverDeviceId;

  final List<Map<String, dynamic>> _vehicleOptions = [
    {
      'name': 'Xe máy',
      'icon': Icons.two_wheeler,
      'color': Colors.blue,
      'speed': '20 - 30 km/h',
      'desc': 'Phù hợp di chuyển trong phố.',
      'isLocked': false, // Mở
    },
    {
      'name': 'Ô tô',
      'icon': Icons.directions_car,
      'color': Colors.orange,
      'speed': '25 - 35 km/h',
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
    'Ô tô': 35.0,
    'Xe đạp': 15.0,
    'Đi bộ': 10.0, // Đi bộ thì ít khi quá nhanh
  };

  final PotholeService _potholeService = PotholeService();
  String? uid;

  @override
  void initState() {
    super.initState();
    getUserID();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    _loadDataFromFirestore();
    _checkPermissionAndStartTracking();
    _subscribeToOnlineUsers();
    _subscribeToPotholes();
  }

  Future<String?> getLocalUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  void getUserID() async {
    uid = await getLocalUserId();
  }

  @override
  void dispose() {
    _updateOnlineStatus(false);
    _assessmentsSub?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    _onlineUsersSub?.cancel();
    _positionStreamSubscription?.cancel();
    _scanTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadDataFromFirestore() async {
    if (_user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          String deviceName = userDoc.get('device_active') ?? "";
          log(deviceName.toString());
          if (deviceName.isNotEmpty) {
            _serverDeviceId = deviceName;
          }
        });
      }
    } catch (e) {
      log("Lỗi lấy dữ liệu từ DB");
    }
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
        'online': isOnline,
        'last_active': FieldValue.serverTimestamp(),
        if (isOnline) 'current_location': {'lat': _currentPosition.latitude, 'lng': _currentPosition.longitude}
      });
    } catch (e) {
      log("Err update online: $e");
    }
  }

  Future<void> _checkPermissionAndStartTracking() async {
    bool hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ShowToast('Không có kết nối Internet. Vui lòng kiểm tra lại Wifi/4G!', false);
      }
      return;
    }
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ShowToast('Vui lòng bật GPS', false);
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) ShowToast('Quyền vị trí bị từ chối', false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Quyền vị trí bị từ chối vĩnh viễn. Hãy mở cài đặt.')));
      return;
    }

    _startLiveLocationTracking();
  }

  void _startLiveLocationTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      LatLng newPos = LatLng(position.latitude, position.longitude);
      double hardwareSpeed = position.speed * 3.6;
      if (hardwareSpeed < 1.0) hardwareSpeed = 0.0;
      setState(() {
        _currentPosition = newPos;
        if (_isTracking) {
          _currentSpeed = hardwareSpeed;
        }
      });
      if (_isTracking && currentUser != null) {
        FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
          'current_location': {'lat': position.latitude, 'lng': position.longitude}
        }).catchError((e) => log("Lỗi update vị trí: $e"));
      }

      if (_isTracking || !_hasFocusedOnce) {
        _mapController.move(newPos, 17.0);
        _hasFocusedOnce = true;
      }
    });
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {
      return false;
    }
    return false;
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
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      if (userDoc.exists) {
        bool isOnline = userDoc.get('online') ?? false;
        _serverDeviceId = userDoc.get('device_active') ?? "";
        log(isOnline.toString());
        if (isOnline && (_serverDeviceId ?? '').isNotEmpty && _serverDeviceId != _currentDeviceId) {
          if (mounted) {
            ShowToast("Tài khoản này đang được quét trên một thiết bị khác!", false);
          }
          return;
        }
      }
    } catch (e) {
      ShowToast("Có lỗi xảy ra", false);
    }
    if (!_isCameraInitialized) {
      await _initCamera();
      if (!_isCameraInitialized) {
        if (mounted) {
          ShowToast("Không thể mở Camera. Hãy kiểm tra quyền truy cập!", false);
        }
        return;
      }
    }
    bool hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ShowToast('Không có kết nối Internet. Vui lòng kiểm tra lại Wifi/4G!', false);
      }
      return;
    }
    setState(() {
      _isTracking = true;
    });
    _subscribeToOnlineUsers();
    setState(() {
      _currentSpeed = 0;
      _lastCaptureTime = DateTime.now();
      _isPausedBySpeed = false;
      _isTooFast = false;
    });
    widget.onTrackingChanged(true);
    WakelockPlus.enable();
    _captureAndUpload(forceCapture: true);
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _calculateSpeedAndDecide();
    });
  }

  void _stopAutoScan() async {
    _scanTimer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _isTracking = false;
      _currentSpeed = 0.0;
    });
    await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'online': false});
    await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'device_active': ''});
    widget.onTrackingChanged(false);
  }

  void _calculateSpeedAndDecide() {
    if (!_isTracking) return;
    _checkCaptureCondition(DateTime.now());
  }

  void _checkCaptureCondition(DateTime now) {
    double limit = _vehicleSpeedLimits[_selectedVehicle] ?? 20.0;
    if (_currentSpeed > limit) {
      if (!_isTooFast) {
        setState(() => _isTooFast = true);
      }
    } else {
      if (_isTooFast) setState(() => _isTooFast = false);
    }
    if (_currentSpeed < 2.0 && _selectedVehicle != 'Đi bộ') {
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
      intervalSeconds = 4;
    } else {
      intervalSeconds = 6;
    }
    if (_isTooFast) intervalSeconds = 4;
    if (_lastCaptureTime == null || now.difference(_lastCaptureTime!).inSeconds >= intervalSeconds) {
      _captureAndUpload();
      _lastCaptureTime = now;
    }
  }

  Future<void> _captureAndUpload({bool forceCapture = false}) async {
    if (_isProcessingFrame || _cameraController == null || !_cameraController!.value.isInitialized) return;
    if (!forceCapture && _currentSpeed < 1.0) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    _isProcessingFrame = true;
    try {
      final XFile image = await _cameraController!.takePicture();
      double lat = _currentPosition.latitude;
      double lng = _currentPosition.longitude;
      String timeReport = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      String? existingDocId;
      for (var pothole in _cachedPotholes) {
        double dist = Geolocator.distanceBetween(lat, lng, pothole['lat'], pothole['lng']);
        if (dist < 15) {
          existingDocId = pothole['id'];
          break;
        }
      }
      if (!mounted) return;
      var aiResult = await _potholeService.processImage(image, context);
      if (aiResult != null) {
        String status = aiResult['status'];
        int count = aiResult['potholeCount'];
        Uint8List imgBytes = aiResult['imageBytes'];
        await _potholeService.saveToFirebase(
          imgBytes,
          status,
          count,
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
          context,
          existingDocId: existingDocId, userId: user.uid,
          userName: user.displayName ?? user.email ?? '',
        );
      }
    } catch (e) {
      ShowToast('Có lỗi xảy ra', false);
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _showCameraMonitor() {
    if (!_isCameraInitialized || _cameraController == null) {
      ShowToast("Camera chưa sẵn sàng!", false);
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
                    Icon(Icons.fiber_manual_record, color: _isTracking ? Colors.red : Colors.grey, size: 14),
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
    _assessmentsSub = FirebaseFirestore.instance.collection('polehole').snapshots().listen((snapshot) {
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
                  _showPotholeInfo(doc);
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

          if (startPoint.latitude != endPoint.latitude || startPoint.longitude != endPoint.longitude) {
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

  void _subscribeToOnlineUsers() async {
    if (_isTracking) {
      log(_currentDeviceId.toString());
      try {
        await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'online': true});
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .update({'device_active': _currentDeviceId});
      } catch (e) {
        log(e.toString());
      }
    }
    _onlineUsersSub =
        FirebaseFirestore.instance.collection('users').where('online', isEqualTo: true).snapshots().listen((snapshot) {
      final List<Marker> markers = [];
      for (var doc in snapshot.docs) {
        if (doc.id == currentUser?.uid) continue;
        final data = doc.data();
        final loc = data['current_location'];
        if (loc != null) {
          double lat = (loc['lat'] is int) ? (loc['lat'] as int).toDouble() : loc['lat'];
          double lng = (loc['lng'] is int) ? (loc['lng'] as int).toDouble() : loc['lng'];
          String name = data['display_name'] ?? data['email'] ?? 'User';
          String? avatar = data['photo_url'];

          markers.add(Marker(
            point: LatLng(lat, lng),
            width: 60,
            height: 80,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: Colors.green, // Viền xanh lá báo online
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5)),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: (avatar == null || avatar.isEmpty)
                        ? const Icon(Icons.person, size: 16, color: Colors.grey)
                        : null,
                  ),
                ),
              ],
            ),
          ));
        }
      }
      setState(() => _onlineUserMarkers = markers);
    });
  }

  void _showPotholeInfo(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    // Tạo Model để truyền sang màn chi tiết
    ReportModel report = ReportModel.fromFirestore(doc);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.45,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Popup
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Chi tiết đánh giá", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                // NÚT CẬP NHẬT Ở ĐÂY
                IconButton(
                  icon: const Icon(Icons.edit_note, color: Color(0xFF6C63FF), size: 30),
                  onPressed: () {
                    Navigator.pop(context); // Đóng popup
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ReportDetailScreen(report: report)),
                    );
                  },
                )
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),
            // Nội dung chi tiết
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(data['image'] ?? '',
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(height: 150, color: Colors.grey[200], child: const Icon(Icons.broken_image))),
            ),
            const SizedBox(height: 10),
            Text("${data['location_start'] ?? '...'}", maxLines: 2),
            const SizedBox(height: 5),
            Text("${DateFormat('dd/MM/yyyy HH:mm').format((data['created_at'] as Timestamp).toDate())}"),
            const SizedBox(height: 5),
            Text("Số lượng: ${data['pothole_count']}"),
            const SizedBox(height: 5),
            Text("Người tạo: ${data['original_reviewer'] ?? 'Ẩn danh'}"),
          ],
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
            color: isLocked ? Colors.grey[100] : (isSelected ? themeColor.withOpacity(0.05) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLocked ? Colors.grey.shade300 : (isSelected ? themeColor : Colors.grey.shade200),
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
                      child: Icon(item['icon'], color: isLocked ? Colors.grey : themeColor, size: 32),
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
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
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
                            color: const Color(0xFF6C63FF).withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                )
                              ]),
                          // Ảnh Avatar
                          child: CircleAvatar(
                            backgroundColor: Colors.grey[200],
                            backgroundImage:
                                currentUser?.photoURL != null ? NetworkImage(currentUser!.photoURL!) : null,
                            child: currentUser?.photoURL == null ? const Icon(Icons.person, color: Colors.grey) : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._onlineUserMarkers,
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
                  boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 15)],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(Icons.speed, color: Colors.redAccent, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      "${_currentSpeed.toStringAsFixed(1)}",
                      style: const TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 5),
                      child: Text("km/h", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
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
                                separatorBuilder: (ctx, i) => const Divider(height: 1, indent: 15, endIndent: 15),
                                itemBuilder: (context, index) {
                                  final item = _suggestions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_on_outlined, color: Colors.grey, size: 20),
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
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Icon(_selectedVehicleIcon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(_selectedVehicle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 15),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("HỆ THỐNG ĐANG CHẠY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        Text("Camera đang phân tích ngầm...", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _stopAutoScan,
                      icon: const Icon(Icons.stop_circle_outlined, size: 40, color: Colors.redAccent),
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
                            fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
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
          Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
