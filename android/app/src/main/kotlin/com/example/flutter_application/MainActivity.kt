package com.example.flutter_application

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAppLabel") {
                try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    val label = packageManager.getApplicationLabel(appInfo).toString()
                    result.success(label)
                } catch (e: Exception) {
                    result.success("畅烁锂电")
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleFileIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleFileIntent(intent)
    }

    /**
     * 统一处理外部传入的配置文件
     * ACTION_VIEW — QQ/微信中"用其他应用打开"
     * ACTION_SEND — 文件管理器中"分享"
     */
    private fun handleFileIntent(intent: Intent?) {
        if (intent == null) return

        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }

        if (uri == null) return

        try {
            val content = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (content.isNullOrBlank()) {
                showToast(msgZh = "无法读取文件内容", msgEn = "Unable to read file")
                return
            }

            if (!content.trimStart().startsWith("Target Model", ignoreCase = true)) {
                showToast(msgZh = "无效的配置文件", msgEn = "Invalid config file")
                return
            }

            val fileName = resolveFileName(content, uri)

            val configDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "bms_configs"
            )
            if (!configDir.exists()) {
                configDir.mkdirs()
            }

            val destFile = File(configDir, fileName)
            destFile.writeText(content)

            showToast(msgZh = "配置导入成功", msgEn = "Config imported")

        } catch (e: Exception) {
            showToast(msgZh = "导入失败: ${e.message}", msgEn = "Import failed: ${e.message}")
        }
    }

    /**
     * 解析文件名：优先查询 ContentProvider 的 DISPLAY_NAME（真实文件名），
     * 避免拿到 content:// URI 中的哈希临时名。
     */
    private fun resolveFileName(content: String, uri: Uri): String {
        // 1. 优先从 ContentProvider 查询真实文件名
        val displayName = queryDisplayName(uri)
        if (!displayName.isNullOrBlank() && displayName.endsWith(".csv", ignoreCase = true)) {
            return displayName
        }

        // 2. 兜底：从 CSV 内容中提取 protocolId 生成文件名
        val firstLine = content.lines().firstOrNull()?.trim() ?: ""
        val targetMatch = Regex("^Target\\s*Model\\s*[,;]\\s*(.+)", RegexOption.IGNORE_CASE)
            .find(firstLine)
        val protocolId = targetMatch?.groupValues?.getOrNull(1)?.trim() ?: "unknown"

        val sdf = SimpleDateFormat("yyyy-MM-dd-HH-mm-ss", Locale.getDefault())
        return "${protocolId}_${sdf.format(Date())}.csv"
    }

    /**
     * 查询 Content URI 对应的真实显示名称
     */
    private fun queryDisplayName(uri: Uri): String? {
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && cursor.moveToFirst()) {
                    return cursor.getString(nameIndex)
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun showToast(msgZh: String, msgEn: String) {
        val msg = if (Locale.getDefault().language == "zh") msgZh else msgEn
        runOnUiThread {
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
        }
    }
}
