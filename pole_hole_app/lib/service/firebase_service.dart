import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widget/show_toast.dart';

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
    required String userId,
    required String userName,
    String? existingDocId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    } else {}
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

      Map<String, dynamic> data = {
        'report_date': dateReport,
        'image': imageUrl,
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
        'userId': userId,
        'updated_at': FieldValue.serverTimestamp(),
        'original_reviewer': userName,
      };

      if (existingDocId != null) {
        DocumentSnapshot oldDoc = await _firestore.collection(_collectionName).doc(existingDocId).get();
        Map<String, dynamic>? oldData = oldDoc.data() as Map<String, dynamic>?;

        Map<String, dynamic> historyItem = {
          'updated_at': DateTime.now(),
          'updater_id': userId,
          'image': imageUrl,
          'status': statusMap,
          'pothole_count': potholeCount,
        };

        await _firestore.collection(_collectionName).doc(existingDocId).update({
          ...data,
          'history_updates': FieldValue.arrayUnion([historyItem]),
        });
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        await _firestore.collection(_collectionName).add(data);
      }
    } catch (e) {
      throw e;
    }
  }

  Stream<QuerySnapshot> getReports() {
    return _firestore.collection(_collectionName).orderBy('created_at', descending: true).snapshots();
  }

  Future<void> updateReportStatus(String docId, bool isFixed) async {
    try {
      await _firestore.collection(_collectionName).doc(docId).update({
        'is_fixed': isFixed,
        'fixed_at': isFixed ? FieldValue.serverTimestamp() : null,
      });
      ShowToast("Cập nhật trạng thái thành công", true);
    } catch (e) {
      ShowToast("Lỗi: Không thể cập nhật", false);
      throw e;
    }
  }

  Future<void> deleteReport(String docId, String imageUrl) async {
    try {
      await _firestore.collection(_collectionName).doc(docId).delete();
      ShowToast("Xóa thành công", true);
    } catch (e) {
      ShowToast("Lỗi: Không thể xóa", false);
      throw e;
    }
  }
}
