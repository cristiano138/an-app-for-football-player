package com.zqsb.football

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// App 内更新：读版本号 / 检查安装权限 / 跳授权设置 / 调起安装界面
object UpdateInstaller {
    private const val CHANNEL = "com.zqsb.football/update"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getAppVersionInfo" -> {
                        val pm = context.packageManager
                        val pkg = context.packageName
                        val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            pm.getPackageInfo(pkg, 0)
                        } else {
                            @Suppress("DEPRECATION")
                            pm.getPackageInfo(pkg, 0)
                        }
                        val versionName = pi.versionName ?: "1.0"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pi.longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            pi.versionCode
                        }
                        result.success(mapOf(
                            "versionName" to versionName,
                            "versionCode" to versionCode,
                            "abis" to Build.SUPPORTED_ABIS.toList()
                        ))
                    }
                    "canInstallUnknown" -> {
                        val can = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(can)
                    }
                    "openUnknownSourceSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${context.packageName}")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank() || !File(path).exists()) {
                            result.error("FILE_NOT_FOUND", "安装包不存在", null)
                            return@setMethodCallHandler
                        }
                        installApk(context, File(path))
                        result.success(true)
                    }
                    "shareImage" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank() || !File(path).exists()) {
                            result.error("FILE_NOT_FOUND", "图片不存在", null)
                            return@setMethodCallHandler
                        }
                        shareImage(context, File(path))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", e.message ?: "操作失败", null)
            }
        }
    }

    private fun installApk(context: Context, apk: File) {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.update.provider",
            apk
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    /// 调起系统分享面板分享图片（速报卡片）
    private fun shareImage(context: Context, image: File) {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.update.provider",
            image
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, "来自「足球速报」App")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(intent, "分享速报卡片").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }
}
