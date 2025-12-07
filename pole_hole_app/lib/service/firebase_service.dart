import 'dart:developer';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  // Khởi tạo instance
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;


  Future<void> saveReport({
  required String imageUrl,
  required String status, 
  required double lat,
  required double lng,
}) async {
  try {
    Map<String, dynamic> statusMap;
    bool needFix = false;

    if (status == 'red') {
      statusMap = {"code": 3, "current_status": "BAD"};
      needFix = true; // Đỏ là cần sửa
    } else if (status == 'yellow') {
      statusMap = {"code": 2, "current_status": "WARNING"};
      needFix = true; // Vàng cũng có thể cần theo dõi/sửa
    } else {
      statusMap = {"code": 1, "current_status": "GOOD"};
      needFix = false; // Xanh thì không cần
    }

    String locationString = "$lat, $lng";

    await _firestore.collection('client').add({
      'date': FieldValue.serverTimestamp(), 
      'image': imageUrl,                    
      'is_fixed': false,                    
      'need_fix': needFix,                  
      'location_start': locationString,     
      'location_end': locationString,       
      'status': statusMap,                  
    });

    print("Đã lưu báo cáo thành công vào collection 'client'!");
    
  } catch (e) {
    print("Lỗi lưu data: $e");
    log("Lỗi lưu data: $e");
    throw e; 
  }
}

  Stream<QuerySnapshot> getReports() {
    return _firestore
        .collection('reports')
        .orderBy('created_at', descending: true) // Mới nhất lên đầu
        .snapshots();
  }

  Future<void> updateReportStatus(String docId, bool isFixed) async {
    try {
      await _firestore.collection('reports').doc(docId).update({
        'is_fixed': isFixed,
        'fixed_at': isFixed ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      print("Lỗi update: $e");
    }
  }
  
  Future<void> deleteReport(String docId, String imageUrl) async {
    try {
      Reference photoRef = _storage.refFromURL(imageUrl);
      await photoRef.delete();

      await _firestore.collection('reports').doc(docId).delete();
      
      print("Đã xóa hoàn toàn!");
    } catch (e) {
      print("Lỗi xóa: $e");
    }
  }
}