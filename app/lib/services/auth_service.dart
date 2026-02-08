import 'package:firebase_auth/firebase_auth.dart';

/// Wrapper um Firebase Auth für aktuellen User und Logout.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<void> logout() async {
    await _auth.signOut();
  }
}
