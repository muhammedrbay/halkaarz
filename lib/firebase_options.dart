import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDg6jiNG5IKIAbS07z8b0qAcuyB0v3pQDc',
    appId:
        '1:306838879846:web:12abc', // Placeholder, we might need real web app id if it fails
    messagingSenderId: '306838879846',
    projectId: 'halkaarz-fb398',
    authDomain: 'halkaarz-fb398.firebaseapp.com',
    storageBucket: 'halkaarz-fb398.firebasestorage.app',
    databaseURL:
        'https://halkaarz-fb398-default-rtdb.europe-west1.firebasedatabase.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDg6jiNG5IKIAbS07z8b0qAcuyB0v3pQDc',
    appId: '1:306838879846:android:35c95070a2de51641af7a7',
    messagingSenderId: '306838879846',
    projectId: 'halkaarz-fb398',
    storageBucket: 'halkaarz-fb398.firebasestorage.app',
    databaseURL:
        'https://halkaarz-fb398-default-rtdb.europe-west1.firebasedatabase.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDg6jiNG5IKIAbS07z8b0qAcuyB0v3pQDc',
    appId: '1:306838879846:ios:e0b0e51...',
    messagingSenderId: '306838879846',
    projectId: 'halkaarz-fb398',
    storageBucket: 'halkaarz-fb398.firebasestorage.app',
    databaseURL:
        'https://halkaarz-fb398-default-rtdb.europe-west1.firebasedatabase.app',
    iosBundleId: 'com.halkaarz.halkaArz',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDg6jiNG5IKIAbS07z8b0qAcuyB0v3pQDc',
    appId: '1:306838879846:ios:e0b0e51...',
    messagingSenderId: '306838879846',
    projectId: 'halkaarz-fb398',
    storageBucket: 'halkaarz-fb398.firebasestorage.app',
    databaseURL:
        'https://halkaarz-fb398-default-rtdb.europe-west1.firebasedatabase.app',
    iosBundleId: 'com.halkaarz.halkaArz',
  );
}
