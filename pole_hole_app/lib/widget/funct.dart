import 'package:cloud_firestore/cloud_firestore.dart';

String formatDateTimeStamp(Timestamp? timestamp) {
  if (timestamp == null) return "Unknown";

  final DateTime date = timestamp.toDate();

  String minute = date.minute.toString().padLeft(2, '0'); // mm (phút)
  String hour = date.hour.toString().padLeft(2, '0'); // hh (giờ)
  String day = date.day.toString().padLeft(2, '0'); // dd (ngày)
  String month = date.month.toString().padLeft(2, '0'); // mm (tháng)
  String year = date.year.toString(); // yyyy (năm)

  return "$minute/$hour - $day/$month/$year";
}
