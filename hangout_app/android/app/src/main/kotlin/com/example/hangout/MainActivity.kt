package com.example.hangout

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // In-app auto-update: lets the Dart side install a downloaded APK
        // through the system package installer (see update_service.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hangout/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstalls" -> result.success(canRequestInstalls())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_path", "No APK path provided", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApk(File(path)))
                        } catch (e: ActivityNotFoundException) {
                            result.error(
                                "no_installer",
                                "No package installer found on this device",
                                null
                            )
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Android 8+ requires the "install unknown apps" permission per source. */
    private fun canRequestInstalls(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    /**
     * Opens the system installer for [file] via FileProvider.
     * Returns "installed" on success, or "needs_permission" after opening
     * the permission settings screen.
     */
    private fun installApk(file: File): String {
        if (!canRequestInstalls()) {
            openInstallSettings()
            return "needs_permission"
        }
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "installed"
    }
}
