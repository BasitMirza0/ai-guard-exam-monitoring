// Compile-only example. Copy to firebase_options.dart for offline tests only.
// Real app setup: run flutterfire configure against your own Firebase project.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: 'CONFIGURE_YOUR_FIREBASE_PROJECT',
    appId: '1:000000000000:android:example',
    messagingSenderId: '000000000000',
    projectId: 'demo-ai-guard',
  );
}
