# FFmpegKit rules
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Keep all FFmpegKit native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep FFmpegKit Config
-keep class com.antonkarpenko.ffmpegkit.FFmpegKitConfig {
    *;
}

# Keep ABI Detection
-keep class com.antonkarpenko.ffmpegkit.AbiDetect {
    *;
}

# Keep all FFmpegKit sessions
-keep class com.antonkarpenko.ffmpegkit.*Session {
    *;
}

# Keep FFmpegKit callbacks
-keep class com.antonkarpenko.ffmpegkit.*Callback {
    *;
}

# Preserve all public classes in ffmpegkit
-keep public class com.antonkarpenko.ffmpegkit.** {
    public *;
}

# Keep reflection-based access
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# Flutter plugin registration can be reached through generated/reflection paths.
# Keep MethodChannel plugins so R8 does not strip them from release APKs.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
