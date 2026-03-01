// File generated from GoogleService-Info.plist (iOS)
// DO NOT EDIT — regenerate with: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web için ayrı FirebaseOptions tanımlamanız gerekiyor.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios; // aynı plist kullan
      case TargetPlatform.android:
        throw UnsupportedError('Android google-services.json gerekmektedir.');
      default:
        throw UnsupportedError(
          'Bu platform için FirebaseOptions tanımlanmadı: $defaultTargetPlatform',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAXoksNncwpWk6bj1YGPJ1ez7kOXmt7sqc',
    appId: '1:306838879846:ios:36612f15aa354ebf1af7a7',
    messagingSenderId: '306838879846',
    projectId: 'halkaarz-fb398',
    storageBucket: 'halkaarz-fb398.firebasestorage.app',
    iosBundleId: 'com.halkaarz.halkaArz',
  );
}
