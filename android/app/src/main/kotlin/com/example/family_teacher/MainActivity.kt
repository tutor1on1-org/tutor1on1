package com.example.family_teacher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    // Explicitly register plugins to avoid missing platform channels on some builds.
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
