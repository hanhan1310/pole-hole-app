import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String _collectionName = 'polehole';

  Future<void> saveReport({
    required String imageUrl,
    required String status,
    required double lat,
    required double lng,
    required String addressStart,
    required String addressEnd,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required String dateReport,
    required String note,
    required int potholeCount,
  }) async {
    try {
      Map<String, dynamic> statusMap;
      bool needFix = false;

      if (status == 'red') {
        statusMap = {"code": 3, "current_status": "BAD"};
        needFix = true;
      } else if (status == 'yellow') {
        statusMap = {"code": 2, "current_status": "WARNING"};
        needFix = true;
      } else {
        statusMap = {"code": 1, "current_status": "GOOD"};
        needFix = false;
      }

      await _firestore.collection(_collectionName).add({
        'created_at': FieldValue.serverTimestamp(),
        'report_date': dateReport,
        'image': imageUrl, // Link Cloudinary
        'is_fixed': false,
        'need_fix': needFix,
        'start_coords': {'lat': startLat, 'lng': startLng},
        'end_coords': {'lat': endLat, 'lng': endLng},
        'location_start': addressStart,
        'location_end': addressEnd,
        'latitude': lat,
        'longitude': lng,
        'status': statusMap,
        'note': note,
        'pothole_count': potholeCount,
      });

      print("✅ Đã lưu báo cáo thành công vào '$_collectionName'!");
    } catch (e) {
      log("❌ Lỗi lưu data: $e");
      throw e;
    }
  }

  // 2. Hàm Lấy dữ liệu (Giữ nguyên)
  Stream<QuerySnapshot> getReports() {
    return _firestore
        .collection(_collectionName)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  Future<void> updateReportStatus(String docId, bool isFixed) async {
    try {
      await _firestore.collection(_collectionName).doc(docId).update({
        'is_fixed': isFixed,
        'fixed_at': isFixed ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      print("Lỗi update: $e");
    }
  }

  Future<void> deleteReport(String docId, String imageUrl) async {
    try {
      await _firestore.collection(_collectionName).doc(docId).delete();
      print("✅ Đã xóa báo cáo khỏi Database!");
    } catch (e) {
      print("❌ Lỗi xóa: $e");
    }
  }
}
