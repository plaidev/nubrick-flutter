//
//  Manager.swift
//  nativebrik_bridge
//
//  Created by Ryosuke Suzuki on 2024/03/10.
//

import Foundation
import Flutter
import UIKit
@_spi(FlutterBridge) import Nubrick

struct EmbeddingEntity {
    let uiview: UIView
    let channel: FlutterMethodChannel
    let accessor: __DO_NOT_USE__NativebrikBridgedViewAccessor?
}

struct RemoteConfigEntity {
    let variant: RemoteConfigVariant?
}

class NativebrikBridgeManager {
    private var nubrickClient: NubrickClient? = nil
    private var embeddingMaps: [String:EmbeddingEntity]
    private var configMaps: [String:RemoteConfigEntity]

    init() {
        self.embeddingMaps = [:]
        self.configMaps = [:]
    }

    func setNativebrikClient(nativebrik: NubrickClient) {
        if self.nubrickClient != nil {
            return print("NativebrikClient is already set")
        }
        self.nubrickClient = nativebrik
        if let vc = UIApplication.shared.delegate?.window??.rootViewController {
            let overlay = nativebrik.experiment.overlayViewController()
            vc.addChild(overlay)
            vc.view.addSubview(overlay.view)
        }
    }

    func getUserId() -> String? {
        guard let nubrickClient = self.nubrickClient else {
            return nil
        }
        return nubrickClient.user.id
    }

    func setUserProperties(properties: [String: Any]) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }
        nubrickClient.user.setProperties(properties)
    }

    func getUserProperties() -> [String: String]? {
        guard let nubrickClient = self.nubrickClient else {
            return nil
        }
        return nubrickClient.user.getProperties()
    }

    // embedding
    func connectEmbedding(id: String, channelId: String, arguments: Any?, messenger: FlutterBinaryMessenger) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }
        let channel = FlutterMethodChannel(name: "Nativebrik/Embedding/\(channelId)", binaryMessenger: messenger)
        let uiview = nubrickClient.experiment.embeddingForFlutterBridge(id, arguments: arguments, onEvent: { event in
            channel.invokeMethod(ON_EVENT_METHOD, arguments: [
                "name": event.name as Any?,
                "deepLink": event.deepLink as Any?,
                "payload": event.payload?.map({ prop in
                    return [
                        "name": prop.name,
                        "value": prop.value,
                        "type": prop.type
                    ]
                }),
            ])
        }, onSizeChange: { width, height in
            channel.invokeMethod(EMBEDDING_SIZE_UPDATE_METHOD, arguments: [
                "width": width,
                "height": height,
            ])
        }) { phase in
            switch phase {
            case .completed(let view):
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "completed")
                return view
            case .notFound:
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "not-found")
                return UIView()
            case .failed:
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "failed")
                return UIView()
            case .loading:
                return UIView()
            }
        }
        let embeedingEntity = EmbeddingEntity(
            uiview: uiview,
            channel: channel,
            accessor: nil
        )
        self.embeddingMaps[channelId] = embeedingEntity
    }

    func disconnectEmbedding(channelId: String) {
        self.embeddingMaps[channelId] = nil
    }

    func getEmbeddingEntity(channelId: String) -> EmbeddingEntity? {
        guard let entity = self.embeddingMaps[channelId] else {
            return nil
        }
        return entity
    }

    // remote config
    func connectRemoteConfig(id: String, channelId: String, onPhase:  @escaping ((RemoteConfigPhase) -> Void)) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }
        let entity = RemoteConfigEntity(variant: nil)
        self.configMaps[channelId] = entity

        nubrickClient.experiment.remoteConfig(id) { phase in
            switch phase {
            case .completed(let config):
                if self.configMaps[channelId] == nil {
                    // disconnected already
                    return
                }
                let entity = RemoteConfigEntity(variant: config)
                self.configMaps[channelId] = entity
                onPhase(phase)
            case .notFound:
                onPhase(phase)
            case .failed:
                onPhase(phase)
            default:
                break
            }
        }
    }

    func disconnectRemoteConfig(channelId: String) {
        self.configMaps[channelId] = nil
    }

    func connectEmbeddingInRemoteConfigValue(key: String, channelId: String, arguments: Any?, embeddingChannelId: String, messenger: FlutterBinaryMessenger) {
        guard let entity = self.configMaps[channelId] else {
            return
        }
        guard let variant = entity.variant else {
            return
        }
        let channel = FlutterMethodChannel(name: "Nativebrik/Embedding/\(embeddingChannelId)", binaryMessenger: messenger)
        guard let uiview = variant.getAsUIView(key, arguments: arguments, onEvent: { event in
            channel.invokeMethod(ON_EVENT_METHOD, arguments: [
                "name": event.name as Any?,
                "deepLink": event.deepLink as Any?,
                "payload": event.payload?.map({ prop in
                    return [
                        "name": prop.name,
                        "value": prop.value,
                        "type": prop.type
                    ]
                }),
            ])
        }, content: { phase in
            switch phase {
            case .completed(let view):
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "completed")
                return view
            case .notFound:
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "not-found")
                return UIView()
            case .failed:
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "failed")
                return UIView()
            case .loading:
                return UIView()
            }
        }) else {
            return
        }
        let embeedingEntity = EmbeddingEntity(
            uiview: uiview,
            channel: channel,
            accessor: nil
        )
        self.embeddingMaps[embeddingChannelId] = embeedingEntity
    }

    func getRemoteConfigValue(channelId: String, key: String) -> String? {
        guard let entity = self.configMaps[channelId] else {
            return nil
        }
        guard let variant = entity.variant else {
            return nil
        }
        return variant.get(key)
    }

    // tooltip
    func connectTooltip(name: String, onFetch: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard let nubrickClient = self.nubrickClient else {
            onError("NativebrikClient is not set")
            return
        }
        Task {
            let result = await nubrickClient.experiment.__do_not_use__fetch_tooltip_data(trigger: name)
            switch result {
            case .success(let data):
                onFetch(data)
            case .failure(let error):
                onError(error.localizedDescription)
            }
        }
    }

    func connectTooltipEmbedding(channelId: String, rootBlock: String, messenger: FlutterBinaryMessenger) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }
        let channel = FlutterMethodChannel(name: "Nativebrik/Embedding/\(channelId)", binaryMessenger: messenger)
        let accessor = nubrickClient.experiment.__do_not_use__render_uiview(
            json: rootBlock,
            onEvent: { event in
                channel.invokeMethod(ON_EVENT_METHOD, arguments: [
                    "name": event.name as Any?,
                    "deepLink": event.deepLink as Any?,
                    "payload": event.payload?.map({ prop in
                        return [
                            "name": prop.name,
                            "value": prop.value,
                            "type": prop.type
                        ]
                    }),
                ])
            },
            onNextTooltip: { pageId in
                channel.invokeMethod(ON_NEXT_TOOLTIP_METHOD, arguments: [
                    "pageId": pageId,
                ])
            },
            onDismiss: {
                channel.invokeMethod(ON_DISMISS_TOOLTIP_METHOD, arguments: nil)
            }
        )
        let embeedingEntity = EmbeddingEntity(
            uiview: accessor.view,
            channel: channel,
            accessor: accessor
        )
        self.embeddingMaps[channelId] = embeedingEntity
    }

    func callTooltipEmbeddingDispatch(channelId: String, event: String) {
        guard let entity = self.embeddingMaps[channelId] else {
            return
        }
        guard let accessor = entity.accessor else {
            return
        }
        do {
            try accessor.dispatch(event: event)
        } catch {}
    }

    func disconnectTooltipEmbedding(channelId: String) {
        self.embeddingMaps[channelId] = nil
    }

    // trigger
    func dispatch(name: String) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }
        nubrickClient.experiment.dispatch(NubrickEvent(name))
    }

    /**
     * Sends crash events from Flutter.
     *
     * This method constructs a crash event and forwards it to the Nativebrik SDK for crash reporting
     * with platform set to "flutter".
     *
     * - Parameter exceptionsList: List of exception records from Flutter
     * - Parameter flutterSdkVersion: The Flutter SDK version
     * - Parameter severity: The severity level ("crash" or "warning")
     */
    func sendFlutterCrash(_ exceptionsList: [[String: Any?]], flutterSdkVersion: String?, severity: String?) {
        guard let nubrickClient = self.nubrickClient else {
            return
        }

        let exceptions = exceptionsList.compactMap { exceptionMap -> ExceptionRecord? in
            let type = exceptionMap["type"] as? String
            let message = exceptionMap["message"] as? String
            let callStacksList = exceptionMap["callStacks"] as? [[String: Any?]]

            let callStacks = callStacksList?.compactMap { frameMap -> StackFrame? in
                StackFrame(
                    fileName: frameMap["fileName"] as? String,
                    className: frameMap["className"] as? String,
                    methodName: frameMap["methodName"] as? String,
                    lineNumber: frameMap["lineNumber"] as? Int
                )
            }

            return ExceptionRecord(
                type: type,
                message: message,
                callStacks: callStacks
            )
        }

        if !exceptions.isEmpty {
            let crashEvent = TrackCrashEvent(
                exceptions: exceptions,
                platform: "flutter",
                flutterSdkVersion: flutterSdkVersion,
                severity: CrashSeverity.from(severity)
            )
            nubrickClient.experiment.sendFlutterCrash(crashEvent)
        }
    }
}

