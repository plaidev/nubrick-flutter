package app.nubrick.flutter.nubrick_flutter

import android.content.Context
import io.nubrick.nubrick.FlutterBridgeApi
import io.nubrick.nubrick.NubrickClient
import io.nubrick.nubrick.FlutterBridge
import io.nubrick.nubrick.data.ExceptionRecord
import io.nubrick.nubrick.data.NotFoundException
import io.nubrick.nubrick.data.StackFrame
import io.nubrick.nubrick.data.CrashSeverity
import io.nubrick.nubrick.data.TrackCrashEvent
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import android.view.View
import android.widget.LinearLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import io.nubrick.nubrick.NubrickEvent
import io.nubrick.nubrick.component.bridge.UIBlockEventBridgeViewModel
import io.nubrick.nubrick.remoteconfig.RemoteConfigVariant
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

internal data class ConfigEntity(val variant: RemoteConfigVariant?, val experimentId: String?)

@OptIn(FlutterBridgeApi::class)
internal class NubrickFlutterManager(private val binaryMessenger: BinaryMessenger) {
    private var nubrickClient: NubrickClient? = null
    private var bridgeClient: FlutterBridge? = null

    private var embeddingMap: MutableMap<String, Any?> = mutableMapOf()
    private var eventBridgeViewMap: MutableMap<String, UIBlockEventBridgeViewModel> = mutableMapOf()
    private var configMap: MutableMap<String, ConfigEntity> = mutableMapOf()

    fun setNubrickClient(client: NubrickClient) {
        this.nubrickClient = client
        this.bridgeClient = FlutterBridge(client)
    }

    fun getUserId(): String? {
        return this.nubrickClient?.user?.id
    }

    fun setUserProperties(properties: Map<String, Any>) {
        this.nubrickClient?.user?.setProperties(properties)
    }

    fun getUserProperties(): Map<String, String>? {
        return this.nubrickClient?.user?.getProperties()
    }

    // embedding
    @OptIn(DelicateCoroutinesApi::class)
    fun connectEmbedding(channelId: String, experimentId: String, componentId: String? = null) {
        val methodChannel = MethodChannel(this.binaryMessenger, "Nubrick/Embedding/$channelId")
        GlobalScope.launch(Dispatchers.IO) {
            val result = bridgeClient?.connectEmbedding(experimentId, componentId)
            if (result == null) {
                GlobalScope.launch(Dispatchers.Main) {
                    methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "not-found")
                }
                return@launch
            }
            result.onSuccess {
                embeddingMap[channelId] = it
                val size = bridgeClient?.computeInitialSize(it)
                GlobalScope.launch(Dispatchers.Main) {
                    methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "completed")
                    methodChannel.invokeMethod(EMBEDDING_SIZE_UPDATE_METHOD, mapOf(
                        "width" to size?.first,
                        "height" to size?.second,
                    ))
                }
            }.onFailure {
                when (it) {
                    is NotFoundException -> {
                        GlobalScope.launch(Dispatchers.Main) {
                            methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "not-found")
                        }
                    }
                    else -> {
                        GlobalScope.launch(Dispatchers.Main) {
                            methodChannel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, "failed")
                        }
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
        val bridgeClient = this.bridgeClient ?: return
        val methodChannel = remember(channelId) {
            MethodChannel(this.binaryMessenger, "Nubrick/Embedding/$channelId")
        }
        val data = this.embeddingMap[channelId]
        val eventBridge = this.eventBridgeViewMap[channelId]
        bridgeClient.render(
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
                    "width" to width,
                    "height" to height,
                ))
            },
            eventBridge = eventBridge
        )
    }

    @Composable
    fun RenderOverlay() {
        nubrickClient?.experiment?.Overlay()
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
        val client = this.nubrickClient ?: return Result.success("not-found")
        val config = client.experiment.remoteConfig(experimentId)
        val variant = config.fetch().getOrElse {
            val status = when (it) {
                is NotFoundException -> "not-found"
                else -> "failed"
            }
            return Result.success(status)
        }
        if (this.configMap[channelId] != null) {
            this.configMap[channelId] = ConfigEntity(variant, variant.experimentId)
        }
        return Result.success("competed")
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

    // tooltip
    suspend fun connectTooltip(name: String): Result<String> {
        if (name.isEmpty()) {
            return Result.success("error: the name is empty")
        }
        val client = this.bridgeClient ?: return Result.success("error: the client is not initialized")
        val tooltip = client.connectTooltip(name).getOrElse {
            return Result.success("error: not found")
        } ?: return Result.success("error: not found")
        return Result.success(tooltip)
    }

    fun connectTooltipEmbedding(channelId: String, rootBlock: String) {
        if (channelId.isEmpty()) return
        embeddingMap[channelId] = rootBlock
        eventBridgeViewMap[channelId] = UIBlockEventBridgeViewModel()
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

    fun dispatch(name: String) {
        this.nubrickClient?.experiment?.dispatch(NubrickEvent(name))
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
                this.nubrickClient?.experiment?.sendFlutterCrash(crashEvent)
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
