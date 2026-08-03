# Keep model classes used by ML Kit libraries
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }

# Keep Flutter TTS
-keep class com.tundralabs.fluttertts.** { *; }

# Keep Google Maps
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.maps.** { *; }

# Don't warn about Kotlin reflection
-dontwarn kotlin.reflect.jvm.internal.**
-dontwarn org.jetbrains.annotations.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep R8 safe
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Keep permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Speech recognition
-keep class com.csdcorp.speech_to_text.** { *; } 