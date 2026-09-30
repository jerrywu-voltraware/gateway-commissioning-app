package com.voltraware.gateway_commissioning

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/** APKs stay in app-private cache; only a verified APK is granted to the installer. */
class AppUpdateBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        private const val SIGNER = "2ae194573a906afd0a4e3ce347a275551e3e5b27a6d4a2644d36d07d102f4b64"
        private const val MAX_BYTES = 150L * 1024 * 1024
    }
    @Volatile private var checking = false
    @Volatile private var generation = 0

    @Suppress("DEPRECATION")
    private fun flags(): Int = if (Build.VERSION.SDK_INT >= 28)
        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun archiveFlags(): Int = if (Build.VERSION.SDK_INT == 28)
        // Android 9 collects archive certificates only when this legacy flag is set.
        flags() or PackageManager.GET_SIGNATURES else flags()

    private fun failure(result: MethodChannel.Result, code: String, error: Exception) {
        // Fixed codes and exception types only: no paths, messages, stack traces or credentials.
        Log.w("AppUpdate", "$code ${error.javaClass.simpleName}")
        result.error(code, "Unable to complete the app update", null)
    }

    @Suppress("DEPRECATION")
    private fun installed(): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, flags())

    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28)
        info.longVersionCode else info.versionCode.toLong()

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): List<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28)
            info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }
            ?: emptyList()
    }

    private fun directory(): File {
        val expected = File(activity.cacheDir.canonicalFile, "app-updates")
        require(expected.canonicalFile == expected)
        require(expected.isDirectory || expected.mkdirs())
        return expected
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "installed" -> {
                    val current = installed()
                    result.success(mapOf("packageName" to current.packageName,
                        "versionName" to (current.versionName ?: ""), "versionCode" to version(current)))
                }
                "downloadPath" -> {
                    check(!checking)
                    result.success(File(directory(), "update.apk").absolutePath)
                }
                "install" -> verifyAndInstall(call, result)
                "cancelInstall" -> { generation += 1; result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            failure(result, "update_prepare_failed", error)
        }
    }

    private fun verifyAndInstall(call: MethodCall, result: MethodChannel.Result) {
        check(!checking)
        val path = call.argument<String>("path") ?: error("path")
        val expectedHash = call.argument<String>("sha256") ?: error("hash")
        val expectedCode = call.argument<Number>("versionCode")?.toLong() ?: error("version")
        require(Regex("[0-9a-f]{64}").matches(expectedHash))
        val allowed = File(directory(), "update.apk")
        require(File(path).canonicalFile == allowed && allowed.canonicalFile == allowed)
        checking = true
        val requestGeneration = generation
        Thread {
            try {
                require(allowed.isFile && allowed.length() in 1..MAX_BYTES)
                val digest = MessageDigest.getInstance("SHA-256")
                allowed.inputStream().buffered().use { stream ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        check(requestGeneration == generation)
                        val count = stream.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                }
                require(hex(digest.digest()) == expectedHash)
                val current = installed()
                val archive = activity.packageManager.getPackageArchiveInfo(allowed.path, archiveFlags())
                    ?: error("archive")
                require(archive.packageName == activity.packageName)
                require(version(archive) == expectedCode && expectedCode > version(current))
                require(signers(current) == listOf(SIGNER) && signers(archive) == listOf(SIGNER))
                Log.i("AppUpdate", "signatures_verified")
                activity.runOnUiThread {
                    try {
                        check(!activity.isFinishing && !activity.isDestroyed)
                        check(activity.hasWindowFocus())
                        check(requestGeneration == generation)
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                            Log.i("AppUpdate", "permission_required")
                            result.success("permission_required")
                        } else {
                            val uri = FileProvider.getUriForFile(activity,
                                "${activity.packageName}.app_updates", allowed)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            activity.startActivity(intent)
                            Log.i("AppUpdate", "installer_opened")
                            result.success("opened")
                        }
                    } catch (error: Exception) {
                        failure(result, "update_install_failed", error)
                    } finally { checking = false }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    checking = false
                    failure(result, "update_verification_failed", error)
                }
            }
        }.start()
    }
}
