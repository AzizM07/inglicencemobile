// Destination :
//   android/app/src/main/kotlin/tn/inglicence/app/MainActivity.kt
// (remplace ton MainActivity.kt existant — c'est le même package)
package tn.inglicence.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Le factoryId doit être IDENTIQUE à celui utilisé côté Dart
        // (NativeAd(factoryId: 'ecoleAdFactory', ...)).
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "ecoleAdFactory",
            EcoleNativeAdFactory(this)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "ecoleAdFactory")
    }
}