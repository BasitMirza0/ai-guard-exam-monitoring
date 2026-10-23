import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'camera_platform.dart';
import '../models/account_status.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Sign Up ───────────────────────────────────────────────────────────────
  Future<User?> signUp(
    String email,
    String password, {
    String role = 'student',
    String name = '',
  }) async {
    if (!const {'student', 'teacher'}.contains(role)) role = 'student';
    try {
      final UserCredential res = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = res.user;
      if (user == null) return null;

      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'name': name.isNotEmpty ? name : email.split('@')[0],
        'role': role,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return user;
    } finally {
      // A profile-write failure must not leave registration signed in.
      await _auth.signOut();
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  // NEVER calls signOut() — main.dart _RoleRouter handles all routing
  // Reads from SERVER to bypass stale cache
  Future<String> login(String email, String password) async {
    try {
      final UserCredential res = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = res.user;
      if (user == null) return 'unknown';

      debugPrint('[AuthService] Signed in');

      try {
        // Source.server — bypasses local cache — fixes stale status bug
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));

        if (!doc.exists) {
          debugPrint('[AuthService] No Firestore doc');
          return 'no_profile';
        }

        final data = doc.data() as Map<String, dynamic>;
        final status = accountStatus(data);
        final role = (data['role'] as String?) ?? 'student';

        debugPrint('[AuthService] status=$status role=$role');

        // Return status — DO NOT signOut()
        // _RoleRouter in main.dart routes:
        //   approved → correct dashboard
        //   pending  → PendingScreen
        //   rejected → PendingScreen
        return status;
      } catch (e) {
        debugPrint('[AuthService] Firestore error: $e');
        return 'firestore_error';
      }
    } catch (e) {
      debugPrint('[AuthService] Login error: $e');
      rethrow;
    }
  }

  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return 'unknown';
      return (doc.data()?['role'] as String?) ?? 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  Future<String> getUserStatus(String uid) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return 'pending';
      return accountStatus(doc.data() ?? {});
    } catch (e) {
      return 'pending';
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      return doc.data();
    } catch (e) {
      return null;
    }
  }

  Future<void> approveUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'status': 'approved',
    });
  }

  Future<void> rejectUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'status': 'rejected',
    });
  }

  Future<void> forgotPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  // Signs in with Google. Returns immediately — let _RoleRouter / _NoProfileScreen
  // in main.dart handle routing. If new user, _NoProfileScreen shows role picker.
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    if (usesIosCamera) {
      final configured = await const MethodChannel(
        'aicheat/ios_configuration',
      ).invokeMethod<bool>('googleSignInConfigured');
      if (configured != true) {
        throw StateError(
          'Google sign-in is not configured for this iPhone app. '
          'Use email/password, or ask the developer to configure the iOS '
          'Google client ID and callback URL scheme.',
        );
      }
    }
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  // Called from _NoProfileScreen after role selection for new Google users.
  Future<void> createGoogleUserProfile(String role) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (!const {'student', 'teacher'}.contains(role)) role = 'student';

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email ?? '',
      'name': user.displayName ?? user.email?.split('@')[0] ?? '',
      'role': role,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'authProvider': 'google',
      'photoURL': user.photoURL,
    });
    await _auth.signOut();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
