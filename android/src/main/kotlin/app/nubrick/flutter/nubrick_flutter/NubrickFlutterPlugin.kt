@file:OptIn(FlutterBridgeApi::class)

package app.nubrick.flutter.nubrick_flutter

import android.content.Context
import app.nubrick.nubrick.FlutterBridge
import app.nubrick.nubrick.FlutterBridgeApi

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal const val EMBEDDING_VIEW_ID = "nubrick-embedding-view"
internal const val OVERLAY_VIEW_ID = "nubrick-overlay-view"
internal const val EMBEDDING_PHASE_UPDATE_METHOD = "embedding-phase-update"
// Sent once after connectEmbedding to provide the initial size so Flutter can reserve
// space for the platform view before Compose mounts. Does not trigger the user's onSizeChange callback.
internal const val EMBEDDING_INITIAL_SIZE_METHOD = "embedding-initial-size"
internal const val EMBEDDING_SIZE_UPDATE_METHOD = "embedding-size-update"
internal const val ON_EVENT_METHOD = "on-event"
internal const val ON_DISPATCH_METHOD = "on-dispatch"
internal const val ON_NEXT_TOOLTIP_METHOD = "on-next-tooltip"
internal const val ON_DISMISS_TOOLTIP_METHOD = "on-dismiss-tooltip"

/** NubrickFlutterPlugin */
class NubrickFlutterPlugin: FlutterPlugin, MethodCallHandler {
    private companion object {
        // Accessed only from the main thread (onAttachedToEngine / onDetachedFromEngine / onMethodCall).
        private var activeCallbackOwner: NubrickFlutterPlugin? = null
    }

    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel : MethodChannel
    private lateinit var context: Context
    private lateinit var manager: NubrickFlutterManager
    private lateinit var sdkScope: CoroutineScope

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = flutterPluginBinding.binaryMessenger
        sdkScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        manager = NubrickFlutterManager(messenger, sdkScope)
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(messenger, "nubrick_flutter")
        channel.setMethodCallHandler(this)

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            OVERLAY_VIEW_ID,
            OverlayViewFactory(manager)
        )
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            EMBEDDING_VIEW_ID,
            NativeViewFactory(manager)
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "connectClient" -> {
                val projectId = call.argument<String>("projectId") as String
                if (projectId.isEmpty()) {
                    result.success("no")
                    return
                }
                activeCallbackOwner = this
                manager.initialize(
                    context = context,
                    projectId = projectId,
                    onEvent = { event ->
                        sdkScope.launch {
                            channel.invokeMethod(ON_EVENT_METHOD, mapOf(
                                "name" to event.name,
                                "deepLink" to event.deepLink,
                                "payload" to event.payload?.map { prop ->
                                    mapOf(
                                        "name" to prop.name,
                                        "value" to prop.value,
                                        "type" to prop.type,
                                    )
                                }
                            ))
                        }
                    },
                    onDispatch = { event ->
                        sdkScope.launch {
                            channel.invokeMethod(ON_DISPATCH_METHOD, mapOf(
                                "name" to event.name
                            ))
                        }
                    },
                    onTooltip = { data, experimentId ->
                        sdkScope.launch {
                            channel.invokeMethod("on-tooltip", mapOf(
                                "data" to data,
                                "experimentId" to experimentId,
                            ))
                        }
                    }
                )
                result.success("ok")
            }
            "getUserId" -> {
                val userId = this.manager.getUserId()
                result.success(userId)
            }
            "setUserProperties" -> {
                val properties = call.arguments as Map<String, Any>
                this.manager.setUserProperties(properties)
                result.success("ok")
            }
            "getUserProperties" -> {
                val properties = this.manager.getUserProperties()
                result.success(properties)
            }
            "connectEmbedding" -> {
                val channelId = call.argument<String>("channelId") as String
                val id = call.argument<String>("id") as String
                this.manager.connectEmbedding(channelId, id)
                result.success("ok")
            }
            "disconnectEmbedding" -> {
                val channelId = call.arguments as String
                this.manager.disconnectEmbedding(channelId)
                result.success("ok")
            }
            "connectRemoteConfig" -> {
                val channelId = call.argument<String>("channelId") as String
                val id = call.argument<String>("id") as String
                sdkScope.launch {
                    val connectResult = withContext(Dispatchers.IO) {
                        manager.connectRemoteConfig(channelId, id)
                    }
                    connectResult.onSuccess {
                        result.success(it)
                    }.onFailure {
                        result.success("failed")
                    }
                }
            }
            "disconnectRemoteConfig" -> {
                val channelId = call.arguments as String
                this.manager.disconnectRemoteConfig(channelId)
                result.success("ok")
            }
            "getRemoteConfigValue" -> {
                val channelId = call.argument<String>("channelId") as String
                val key = call.argument<String>("key") as String
                val value = this.manager.getRemoteConfigValue(channelId, key)
                result.success(value)
            }
            "connectEmbeddingInRemoteConfigValue" -> {
                val channelId = call.argument<String>("channelId") as String
                val embeddingChannelId = call.argument<String>("embeddingChannelId") as String
                val key = call.argument<String>("key") as String
                this.manager.connectEmbeddingInRemoteConfigValue(channelId, key, embeddingChannelId)
                result.success("ok")
            }

            // tooltip
            "connectTooltipEmbedding" -> {
                val channelId = call.argument<String>("channelId") as String
                val rootBlock = call.argument<String>("json") as String
                this.manager.connectTooltipEmbedding(channelId, rootBlock)
                result.success("ok")
            }
            "callTooltipEmbeddingDispatch" -> {
                val channelId = call.argument<String>("channelId") as String
                val event = call.argument<String>("event") as String
                sdkScope.launch {
                    withContext(Dispatchers.IO) {
                        manager.callTooltipEmbeddingDispatch(channelId, event)
                    }
                    result.success("ok")
                }
            }
            "disconnectTooltipEmbedding" -> {
                val channelId = call.arguments as String
                this.manager.disconnectTooltip(channelId)
                result.success("ok")
            }
            "appendTooltipExperimentHistory" -> {
                val experimentId = call.argument<String>("experimentId") as String
                this.manager.appendTooltipExperimentHistory(experimentId)
                result.success("ok")
            }

            "dispatch" -> {
                val event = call.arguments as String
                this.manager.dispatch(event)
                result.success("ok")
            }
            "recordCrash" -> {
                try {
                    val errorData = call.arguments as? Map<*, *>
                    if (errorData == null) {
                        result.error("CRASH_REPORT_ERROR", "Invalid error data format", null)
                        return
                    }

                    val exceptionsList = errorData["exceptions"] as? List<*>
                    if (exceptionsList == null) {
                        result.error("CRASH_REPORT_ERROR", "Missing exceptions list", null)
                        return
                    }

                    val exceptions = exceptionsList.mapNotNull { it as? Map<*, *> }
                        .map { it.mapKeys { entry -> entry.key.toString() } }
                    val flutterSdkVersion = errorData["flutterSdkVersion"] as? String
                    val severity = errorData["severity"] as? String ?: "crash"
                    this.manager.recordFlutterExceptions(exceptions, flutterSdkVersion, severity)
                    result.success("ok")
                } catch (e: Exception) {
                    result.error("CRASH_REPORT_ERROR", "Failed to record crash: ${e.message}", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (activeCallbackOwner === this) {
            activeCallbackOwner = null
            FlutterBridge.clearCallbacks()
        }
        sdkScope.cancel()
    }
}

// Helper method to parse Flutter stack trace into Java stack trace elements
//
// Flutter Stack Trace
// #0      NubrickDispatcher.dispatch (package:nubrick_flutter/dispatcher.dart:10:5)
// #1      _MyAppState.build.<anonymous closure> (package:nubrick_flutter_example/main.dart:91:42)
// ....
//
// Kotlin.StackTraceElement
// StackTraceElement("NubrickDispatcher", "dispatch", "package:nubrick_flutter/dispatcher.dart", 10)
// ...
fun parseStackTraceElements(stackTraceString: String): Array<StackTraceElement> {
    val lines = stackTraceString.split("\n")
    return lines.mapNotNull { line ->
        try {
            // Simple parsing of Flutter stack trace format
            // This is a basic implementation and might need to be enhanced
            val trimmed = line.trim()
            if (trimmed.isEmpty()) return@mapNotNull null

            // Try to extract file, class, method and line information
            val parts = trimmed.split(" ")
            var fileInfo = parts.lastOrNull() ?: return@mapNotNull null
            // this cannot handle generics methods if the generics is <anonymous closure>.
            val methodPart = parts.takeLast(2).firstOrNull() ?: "unknown.unknown"

            // Default values
            var className = "unknown"
            var methodName = "unknown"
            var fileName = "unknown"
            var lineNumber = -1

            // Try to parse file and line information
            if (fileInfo.contains(":")) {
                fileInfo = fileInfo.substringAfter("(").substringBeforeLast(")")
                val fileParts = fileInfo.split(":").map { it.trim() }
                val packageName = fileParts.getOrNull(0) ?: "unknown"
                val flutterFileName = fileParts.getOrNull(1) ?: "unknown"
                fileName = "$packageName:$flutterFileName"
                lineNumber = fileParts.getOrNull(2)?.toIntOrNull() ?: -1
            }

            // Try to extract method name if available
            methodPart.let {
                val lastDot = methodPart.indexOf(".")
                if (lastDot > 0) {
                    className = methodPart.substring(0, lastDot)
                    methodName = methodPart.substring(lastDot + 1)
                }
            }

            StackTraceElement(className, methodName, fileName, lineNumber)
        } catch (e: Exception) {
            // If parsing fails, create a generic stack trace element
            StackTraceElement("flutter.Error", "unparseable", "flutter", -1)
        }
    }.toTypedArray()
}
