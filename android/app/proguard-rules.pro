# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components) — referenced by Flutter engine but not used
-dontwarn com.google.android.play.core.**

# http / okhttp
-dontwarn okhttp3.**
-dontwarn okio.**