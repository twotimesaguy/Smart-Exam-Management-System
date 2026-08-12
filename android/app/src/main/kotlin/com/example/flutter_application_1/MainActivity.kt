package com.example.flutter_application_1

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sems/pdf_opener"
        ).setMethodCallHandler { call, result ->
            if (call.method != "openPdf" && call.method != "openFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("missing_path", "File path is missing.", null)
                return@setMethodCallHandler
            }
            val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

            try {
                openFile(path, mimeType)
                result.success(null)
            } catch (error: ActivityNotFoundException) {
                result.error(
                    "no_file_app",
                    "No app is installed on this device to open this file.",
                    null
                )
            } catch (error: Exception) {
                result.error("open_failed", error.message, null)
            }
        }
    }

    private fun openFile(path: String, mimeType: String) {
        val file = fileForProvider(File(path))
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            clipData = ClipData.newUri(contentResolver, "Export", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(Intent.createChooser(intent, "Open File"))
    }

    private fun fileForProvider(source: File): File {
        if (!source.exists()) {
            throw IllegalArgumentException("File was not created.")
        }

        val exportDir = File(cacheDir, "exports").apply {
            mkdirs()
        }
        val target = File(exportDir, source.name)
        if (source.canonicalPath != target.canonicalPath) {
            source.copyTo(target, overwrite = true)
        }
        return target
    }
}
