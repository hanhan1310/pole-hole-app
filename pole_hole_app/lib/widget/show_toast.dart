import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

void ShowToast(String message, bool status) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.TOP,
    backgroundColor: status ? Colors.green.withOpacity(0.6) : Colors.red.withOpacity(0.8),
    textColor: status ? Colors.black : Colors.white,
    fontSize: 16.0,
  );
}
