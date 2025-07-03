package com.poof.flutterauth

import android.content.Context
import androidx.annotation.NonNull
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter bridge for the Play Integrity *Standard* API (library 1.4.0).
 */
class StandardIntegrityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var stdMgr: StandardIntegrityManager
    private lateinit var ctx: Context

    private var provider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var currentProject: Long = -1L

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "standard_integrity")
        channel.setMethodCallHandler(this)

        stdMgr = IntegrityManagerFactory.createStandard(ctx)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        provider = null          // no explicit cleanup method in 1.4.0
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getStandardIntegrityToken") {
            result.notImplemented(); return
        }
        val reqHash = call.argument<String>("requestHash") ?: ""
        val gcpProject = call.argument<Number>("gcpProjectNumber")?.toLong() ?: 0L
        obtainToken(reqHash, gcpProject, result)
    }

    private fun obtainToken(
        reqHashB64: String,
        gcpProject: Long,
        sink: MethodChannel.Result
    ) {
        if (provider != null && currentProject == gcpProject) {
            requestToken(reqHashB64, sink); return
        }

        val prep = StandardIntegrityManager.PrepareIntegrityTokenRequest
            .builder()
            .setCloudProjectNumber(gcpProject)
            .build()

        stdMgr.prepareIntegrityToken(prep)
            .addOnSuccessListener { p ->
                provider = p
                currentProject = gcpProject
                requestToken(reqHashB64, sink)
            }
            .addOnFailureListener { e -> handleError("integrity_prepare_error", e, sink) }
    }

    private fun requestToken(reqHashB64: String, sink: MethodChannel.Result) {
        val prov = provider ?: run {
            sink.error("integrity_no_provider", "Provider is null – prepare step failed", null)
            return
        }

        val req = StandardIntegrityManager.StandardIntegrityTokenRequest
            .builder()
            .setRequestHash(reqHashB64)
            .build()

        prov.request(req)
            .addOnSuccessListener { resp -> sink.success(resp.token()) }
            .addOnFailureListener { e -> handleError("integrity_request_error", e, sink) }
    }

    private fun handleError(prefix: String, e: Exception, sink: MethodChannel.Result) {
        if (e is StandardIntegrityException) {
            val code = e.errorCode   // Int in 1.4.0
            sink.error("$prefix/$code", e.localizedMessage, code)
        } else {
            sink.error(prefix, e.localizedMessage, null)
        }
    }
}

