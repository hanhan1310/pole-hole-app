import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    try {
      UserCredential cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      String uid = cred.user!.uid;
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(cred.user!.uid).get();
      if (userDoc.exists) {
        if (email == "admin123@gmail.com") {
          return await _saveUserIdToLocal(uid);
        }
        String status = userDoc.get('status') ?? 'active';

        if (status == 'locked' || status == 'deleted') {
          await _auth.signOut();
          throw FirebaseAuthException(code: 'user-disabled', message: 'Tài khoản đã bị khóa hoặc xóa.');
        }
        bool isApproved = userDoc.get('is_approved') ?? false;
        String role = userDoc.get('role') ?? 'surveyor';
        if (role == 'surveyor' && !isApproved) {
          await _auth.signOut();
          throw FirebaseAuthException(
              code: 'user-not-approved', message: 'Tài khoản chưa được duyệt hoặc mã dự án không hợp lệ.');
        }
        await _saveUserIdToLocal(uid);
      } else {
        if (email == "admin123@gmail.com") {
          await _firestore.collection('users').doc(cred.user!.uid).set({
            'email': email,
            'role': 'admin',
            'is_approved': true,
            'status': 'active',
            'created_at': FieldValue.serverTimestamp(),
            'online': true,
            'display_name': 'Super Admin',
          });
          await _saveUserIdToLocal(cred.user!.uid);
          return;
        } else {
          throw FirebaseAuthException(
              code: 'user-not-approved', message: 'Tài khoản chưa được duyệt hoặc mã dự án không hợp lệ.');
        }
      }
    } on FirebaseAuthException catch (e) {
      rethrow;
    } catch (e) {
      await _auth.signOut();
      throw FirebaseAuthException(code: 'unknown-error', message: 'Lỗi hệ thống: $e');
    }
  }

  Future<void> signUp({required String email, required String password, required String inviteCode}) async {
    const String secretCode = "POLEHOLE123";
    bool isApproved = false;
    if (inviteCode.trim().toUpperCase() == secretCode) {
      isApproved = true;
    } else {
      throw FirebaseAuthException(code: 'invalid-invite-code', message: 'Mã dự án/Mã cá nhân không chính xác.');
    }
    UserCredential cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    String uid = cred.user!.uid;
    await _firestore.collection('users').doc(cred.user!.uid).set({
      'email': email,
      'role': 'surveyor',
      'is_approved': isApproved,
      'created_at': FieldValue.serverTimestamp(),
      'status': 'active',
      'online': false,
      'display_name': null,
      'photo_url': null,
    });
    await _saveUserIdToLocal(uid);
  }

  Future<void> signOut() async {
    if (currentUser != null) {
      try {
        await _firestore.collection('users').doc(currentUser!.uid).update({'online': false});
      } catch (e) {}
    }
    await _clearLocalUserId();
    await _auth.signOut();
  }

  Future<void> _saveUserIdToLocal(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', uid);
  }

  Future<void> _clearLocalUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
  }

  Future<bool> checkAuthStatusOnAppStart() async {
    await Future.delayed(const Duration(milliseconds: 500));
    User? user = _auth.currentUser;

    // 1. Nếu chưa đăng nhập -> False
    if (user == null) return false;
    try {
      await user.reload(); // <--- THÊM DÒNG NÀY: Ép cập nhật trạng thái mới nhất
      user = _auth.currentUser; // Lấy lại user sau khi reload
    } catch (e) {
      // Nếu reload lỗi (mất mạng, token hết hạn...) -> coi như chưa đăng nhập
      return false;
    }

    if (user == null) return false;

    try {
      // 2. Lấy dữ liệu mới nhất từ Firestore
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        // Nếu user đã bị xóa bên database -> Đăng xuất luôn
        await _auth.signOut();
        return false;
      }

      // 3. Kiểm tra các điều kiện chặn (Logic giống hệt hàm signIn)
      String status = userDoc.get('status') ?? 'active';
      String role = userDoc.get('role') ?? 'surveyor';
      bool isApproved = userDoc.get('is_approved') ?? false;

      // Case 1: Bị khóa hoặc xóa mềm
      if (status == 'locked' || status == 'deleted') {
        await _auth.signOut(); // Đá văng ra
        return false;
      }

      // Case 2: Surveyor chưa được duyệt
      if (role == 'surveyor' && !isApproved) {
        await _auth.signOut(); // Đá văng ra
        return false;
      }

      // Update online status khi mở lại app
      await _firestore.collection('users').doc(user.uid).update({'online': true});

      // Nếu mọi thứ OK -> True
      return true;
    } catch (e) {
      // Lỗi mạng hoặc lỗi khác -> Có thể cho qua hoặc bắt đăng nhập lại tùy policy
      // Ở đây an toàn nhất là bắt đăng nhập lại
      await _auth.signOut();
      return false;
    }
  }
}
