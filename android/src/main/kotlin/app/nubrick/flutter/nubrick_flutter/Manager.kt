@file:OptIn(FlutterBridgeApi::class)

package app.nubrick.flutter.nubrick_flutter

import android.content.Context
import app.nubrick.nubrick.Config
import app.nubrick.nubrick.Event
import app.nubrick.nubrick.FlutterBridgeApi
import app.nubrick.nubrick.FlutterBridge
import app.nubrick.nubrick.NubrickSDK
import app.nubrick.nubrick.data.ExceptionRecord
import app.nubrick.nubrick.data.NotFoundException
import app.nubrick.nubrick.data.StackFrame
import app.nubrick.nubrick.data.CrashSeverity
import app.nubrick.nubrick.data.TrackCrashEvent
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import android.view.View
import android.widget.LinearLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import app.nubrick.nubrick.NubrickEvent
import app.nubrick.nubrick.NubrickSize
import app.nubrick.nubrick.NubrickProvider
import app.nubrick.nubrick.component.bridge.UIBlockActionBridge
import app.nubrick.nubrick.remoteconfig.RemoteConfigVariant
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal data class ConfigEntity(val variant: RemoteConfigVariant?, val experimentId: String?)

private fun nubrickSizeToMessage(size: NubrickSize): Map<String, Any?> {
    return when (size) {
        is NubrickSize.Fixed -> mapOf(
            "kind" to "fixed",
            "value" to size.value.toDouble(),
        )
        NubrickSize.Fill -> mapOf(
            "kind" to "fill",
        )
    }
}

internal class NubrickFlutterManager(
    private val binaryMessenger: BinaryMessenger,
    private val scope: CoroutineScope
) {
    private var embeddingMap: MutableMap<String, Any?> = mutableMapOf()
    private var eventBridgeViewMap: MutableMap<String, UIBlockActionBridge> = mutableMapOf()
    private var configMap: MutableMap<String, ConfigEntity> = mutableMapOf()

    fun initialize(
        context: Context,
        projectId: String,
        onEvent: (event: Event) -> Unit,
        onDispatch: (event: NubrickEvent) -> Unit,
        onTooltip: (data: String, experimentId: String) -> Unit
    ) {
        // Callbacks are passed at init to avoid missing events fired during initialization.
        NubrickSDK.initialize(
            context,
            Config(
                projectId,
                onEvent = onEvent,
                onDispatch = onDispatch,
            ),
            onTooltip = onTooltip
        )
        // initialize is idempotent — on subsequent calls it's a no-op, so update callbacks separately.
        FlutterBridge.updateCallbacks(
            onEvent = onEvent,
            onDispatch = onDispatch,
            onTooltip = onTooltip
        )
    }

    fun getUserId(): String? {
        return NubrickSDK.getUserId()
    }

    fun setUserProperties(properties: Map<String, Any>) {
        NubrickSDK.setUserProperties(properties)
    }

    fun getUserProperties(): Map<String, String>? {
        return NubrickSDK.getUserProperties()
    }

    // embedding
    fun connectEmbedding(channelId: String, experimentId: String, componentId: String? = null) {
        val methodChannel = MethodChannel(this.binaryMessenger, "Nubrick/Embedding/$channelId")
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                FlutterBridge.connectEmbedding(experimentId, componentId)
            }
            result.onSuccess {
                embeddingMap[channelId] = it
                val size = FlutterBridge.computeInitialSize(it)
                methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "completed")
                methodChannel.invokeMethod(EMBEDDING_INITIAL_SIZE_METHOD, mapOf(
                    "width" to nubrickSizeToMessage(size.first),
                    "height" to nubrickSizeToMessage(size.second),
                ))
            }.onFailure {
                when (it) {
                    is NotFoundException -> {
                        methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "not-found")
                    }
                    else -> {
                        methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "failed")
                    }
                }
            }
        }
    }

    fun disconnectEmbedding(channelId: String) {
        embeddingMap.remove(channelId)
    }

    @Composable
    fun Render(channelId: String, arguments: Any?, modifier: Modifier = Modifier) {
        if (channelId.isEmpty()) {
            return
        }
        val methodChannel = remember(channelId) {
            MethodChannel(this.binaryMessenger, "Nubrick/Embedding/$channelId")
        }
        val data = this.embeddingMap[channelId]
        val eventBridge = this.eventBridgeViewMap[channelId]
        FlutterBridge.render(
            modifier,
            arguments,
            data,
            onEvent = { event ->
                methodChannel.invokeMethod(ON_EVENT_METHOD, mapOf(
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
            },
            onNextTooltip = { pageId ->
                methodChannel.invokeMethod(ON_NEXT_TOOLTIP_METHOD, mapOf(
                    "pageId" to pageId,
                ))
            },
            onDismiss = {
                methodChannel.invokeMethod(ON_DISMISS_TOOLTIP_METHOD, null)
            },
            onSizeChange = { width, height ->
                methodChannel.invokeMethod(EMBEDDING_SIZE_UPDATE_METHOD, mapOf(
                    "width" to nubrickSizeToMessage(width),
                    "height" to nubrickSizeToMessage(height),
                ))
            },
            eventBridge = eventBridge
        )
    }

    @Composable
    fun RenderOverlay() {
        NubrickProvider {}
    }

    // remote config
    suspend fun connectRemoteConfig(channelId: String, experimentId: String): Result<String> {
        if (channelId.isEmpty()) {
            return Result.success("not-found")
        }
        this.configMap[channelId] = ConfigEntity(null, null)

        if (experimentId.isEmpty()) {
            return Result.success("not-found")
        }
        val remoteConfig = NubrickSDK.remoteConfig(experimentId).getOrElse {
            return Result.success("not-found")
        }
        val variant = remoteConfig.fetch().getOrElse {
            val status = when (it) {
                is NotFoundException -> "not-found"
                else -> "failed"
            }
            return Result.success(status)
        }
        if (this.configMap[channelId] != null) {
            this.configMap[channelId] = ConfigEntity(variant, variant.experimentId)
        }
        return Result.success("completed")
    }

    fun disconnectRemoteConfig(channelId: String) {
        this.configMap.remove(channelId)
    }

    fun getRemoteConfigValue(channelId: String, key: String): String? {
        if (channelId.isEmpty()) return null
        if (key.isEmpty()) return null
        val config = this.configMap[channelId] ?: return null
        val variant = config.variant ?: return null
        return variant.get(key)
    }

    fun connectEmbeddingInRemoteConfigValue(channelId: String, key: String, embeddingChannelId: String) {
        if (channelId.isEmpty()) return
        val config = this.configMap[channelId] ?: return
        val variant = config.variant ?: return
        val componentId = variant.get(key) ?: return
        val experimentId = config.experimentId ?: return
        this.connectEmbedding(embeddingChannelId, experimentId, componentId)
    }

    fun connectTooltipEmbedding(channelId: String, rootBlock: String) {
        if (channelId.isEmpty()) return
        embeddingMap[channelId] = rootBlock
        eventBridgeViewMap[channelId] = UIBlockActionBridge()
    }

    suspend fun callTooltipEmbeddingDispatch(channelId: String, event: String) {
        if (channelId.isEmpty() || event.isEmpty()) return
        val eventBridge = eventBridgeViewMap[channelId] ?: return
        eventBridge.dispatch(event)
    }

    fun disconnectTooltip(channelId: String) {
        if (channelId.isEmpty()) return
        embeddingMap.remove(channelId)
        eventBridgeViewMap.remove(channelId)
    }

    fun appendTooltipExperimentHistory(experimentId: String) {
        if (experimentId.isEmpty()) return
        NubrickSDK.appendTooltipExperimentHistory(experimentId)
    }

    fun dispatch(name: String) {
        NubrickSDK.dispatch(NubrickEvent(name))
    }

    /**
     * Records exceptions from Flutter.
     *
     * This method constructs a crash event and forwards it to the Nubrick SDK for crash reporting
     * with platform set to "flutter".
     *
     * @param exceptionsList List of exception records from Flutter
     * @param flutterSdkVersion The Flutter SDK version
     * @param severity The severity level ("crash" or "warning")
     */
    fun recordFlutterExceptions(exceptionsList: List<Map<String, Any?>>, flutterSdkVersion: String?, severity: String?) {
        try {
            val exceptions = exceptionsList.mapNotNull { exceptionMap ->
                try {
                    val type = exceptionMap["type"] as? String
                    val message = exceptionMap["message"] as? String
                    val callStacksList = exceptionMap["callStacks"] as? List<*>

                    val callStacks = callStacksList?.mapNotNull { frameMap ->
                        try {
                            val frame = frameMap as? Map<*, *>
                            StackFrame(
                                fileName = frame?.get("fileName") as? String,
                                className = frame?.get("className") as? String,
                                methodName = frame?.get("methodName") as? String,
                                lineNumber = (frame?.get("lineNumber") as? Number)?.toInt()
                            )
                        } catch (e: Exception) {
                            null
                        }
                    }

                    ExceptionRecord(
                        type = type,
                        message = message,
                        callStacks = callStacks
                    )
                } catch (e: Exception) {
                    null
                }
            }

            if (exceptions.isNotEmpty()) {
                val crashEvent = TrackCrashEvent(
                    exceptions = exceptions,
                    platform = "flutter",
                    flutterSdkVersion = flutterSdkVersion,
                    severity = CrashSeverity.from(severity)
                )
                NubrickSDK.sendFlutterCrash(crashEvent)
            }
        } catch (e: Exception) {
            // Silently fail to avoid causing crashes in error reporting
        }
    }
}

internal class OverlayViewFactory(private val manager: NubrickFlutterManager): PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return OverlayView(context, manager)
    }
}

internal class OverlayView(context: Context, manager: NubrickFlutterManager): PlatformView {
    private val view: ComposeView

    override fun getView(): View {
        return view
    }

    override fun dispose() {}

    init {
        view = ComposeView(context).apply {
            setContent {
                manager.RenderOverlay()
            }
        }
    }
}

internal class NativeViewFactory(private val manager: NubrickFlutterManager): PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as Map<*, *>?
        val channelId = creationParams?.get("channelId") as String
        val arguments = creationParams["arguments"]
        return NativeView(context, channelId, arguments, manager)
    }
}

internal class NativeView(context: Context, channelId: String, arguments: Any?, manager: NubrickFlutterManager): PlatformView {
    private val view: ComposeView

    override fun getView(): View {
        return view
    }

    override fun dispose() {}

    init {
        val param = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        view = ComposeView(context).apply {
            setContent {
                manager.Render(channelId, arguments)
            }
            layoutParams = param
        }
    }
}
