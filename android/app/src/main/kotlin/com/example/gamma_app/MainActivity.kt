package com.example.gamma_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val EXTERNAL_URL_CHANNEL = "gamma_app/external_url"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_URL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.error("invalid_url", "La URL está vacía.", null)
                return@setMethodCallHandler
            }

            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "open_url_failed",
                    error.message ?: "No se pudo abrir el navegador.",
                    null,
                )
            }
        }
    }
}
