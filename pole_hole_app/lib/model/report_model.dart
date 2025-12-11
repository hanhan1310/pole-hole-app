import 'package:cloud_firestore/cloud_firestore.dart';

class ReportModel {
  final String id;
  final String imageUrl;
  final String addressStart;
  final String? addressEnd;
  final String? note;
  final String repairStatus;
  final DateTime createdAt;
  final int potholeCount;
  final int statusCode;

  // --- 3 TRƯỜNG MỚI ---
  final String originalReviewer; // Người tạo báo cáo ban đầu
  final String? updater; // Người cập nhật sau cùng
  final DateTime? updatedAt; // Thời gian cập nhật sau cùng

  ReportModel({
    required this.id,
    required this.imageUrl,
    required this.addressStart,
    this.addressEnd,
    this.note,
    required this.repairStatus,
    required this.createdAt,
    required this.potholeCount,
    required this.statusCode,
    // --- THÊM VÀO CONSTRUCTOR ---
    required this.originalReviewer,
    this.updater,
    this.updatedAt,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    final statusMap = data['status'] as Map<String, dynamic>?;
    final int code = statusMap?['code'] ?? 1;

    final Timestamp? timestamp = data['created_at'];
    final DateTime date = timestamp != null ? timestamp.toDate() : DateTime.now();

    // Parse thời gian cập nhật (nếu có)
    final Timestamp? updateTimestamp = data['updated_at'];
    final DateTime? updateDate = updateTimestamp?.toDate();

    return ReportModel(
      id: doc.id,
      imageUrl: data['image'] ?? '',
      addressStart: data['location_start'] ?? 'Không xác định',
      addressEnd: data['location_end'],
      note: data['note'],
      repairStatus: data['repair_status'] ?? 'pending',
      createdAt: date,
      potholeCount: data['pothole_count'] ?? 0,
      statusCode: code,

      // --- MAP DỮ LIỆU MỚI ---
      // Nếu data cũ chưa có trường này, mặc định là "Người đánh giá" như bạn yêu cầu
      originalReviewer: data['original_reviewer'] ?? 'Người đánh giá',
      updater: data['updater'],
      updatedAt: updateDate,
    );
  }
}
