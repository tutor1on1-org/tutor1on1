package com.example.tutor1on1

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private var pendingImportResult: MethodChannel.Result? = null
  private val importRequestCode = 42011

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    // Explicitly register plugins to avoid missing platform channels on some builds.
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "tutor1on1/course_import",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "pickAndImportCourseFolder" -> {
          if (pendingImportResult != null) {
            result.error("in_progress", "Folder picker already open.", null)
            return@setMethodCallHandler
          }
          pendingImportResult = result
          try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            startActivityForResult(intent, importRequestCode)
          } catch (e: Exception) {
            pendingImportResult = null
            result.error("launch_failed", e.message ?: "Failed to open picker.", null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode != importRequestCode) {
      return
    }
    val result = pendingImportResult
    pendingImportResult = null
    if (result == null) {
      return
    }
    if (resultCode != Activity.RESULT_OK) {
      result.success(null)
      return
    }
    val uri: Uri? = data?.data
    if (uri == null) {
      result.success(null)
      return
    }
    try {
      val flags = data?.flags ?: 0
      val takeFlags = flags and
        (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
      contentResolver.takePersistableUriPermission(uri, takeFlags)
    } catch (_: SecurityException) {
      // Best effort; still try to read once.
    }
    val docTree = DocumentFile.fromTreeUri(this, uri)
    if (docTree == null || !docTree.isDirectory) {
      result.error("invalid_tree", "Selected folder is not readable.", null)
      return
    }
    val baseRoot = getExternalFilesDir(null) ?: filesDir
    val coursesRoot = File(baseRoot, "imported_courses")
    val rawName = docTree.name?.trim()
    val folderName = if (rawName.isNullOrEmpty()) "course" else rawName
    val targetDir = createUniqueDir(coursesRoot, folderName)
    Thread {
      try {
        copyTree(docTree, targetDir)
        runOnUiThread {
          result.success(targetDir.absolutePath)
        }
      } catch (e: Exception) {
        runOnUiThread {
          result.error("copy_failed", e.message ?: "Failed to import folder.", null)
        }
      }
    }.start()
  }

  private fun createUniqueDir(root: File, name: String): File {
    if (!root.exists()) {
      root.mkdirs()
    }
    var candidate = File(root, name)
    var index = 1
    while (candidate.exists()) {
      candidate = File(root, "${name}_$index")
      index += 1
    }
    candidate.mkdirs()
    return candidate
  }

  private fun copyTree(source: DocumentFile, target: File) {
    if (!target.exists()) {
      target.mkdirs()
    }
    for (child in source.listFiles()) {
      val childName = child.name?.trim().takeIf { !it.isNullOrEmpty() } ?: continue
      val targetChild = File(target, childName)
      if (child.isDirectory) {
        copyTree(child, targetChild)
      } else if (child.isFile) {
        copyFile(child, targetChild)
      }
    }
  }

  private fun copyFile(source: DocumentFile, target: File) {
    contentResolver.openInputStream(source.uri)?.use { input ->
      FileOutputStream(target).use { output ->
        input.copyTo(output)
      }
    } ?: throw IllegalStateException("Unable to open ${source.uri}")
  }
}
