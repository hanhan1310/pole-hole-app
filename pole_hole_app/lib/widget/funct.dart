import 'package:cloud_firestore/cloud_firestore.dart';

String formatDateTimeStamp(Timestamp? timestamp) {
  if (timestamp == null) return "Unknown";

  final DateTime date = timestamp.toDate();

  String minute = date.minute.toString().padLeft(2, '0');
  String hour = date.hour.toString().padLeft(2, '0');
  String day = date.day.toString().padLeft(2, '0');
  String month = date.month.toString().padLeft(2, '0');
  String year = date.year.toString();

  return "$minute/$hour - $day/$month/$year";
}
