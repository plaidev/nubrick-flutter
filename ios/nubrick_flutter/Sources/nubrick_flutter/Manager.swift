//
//  Manager.swift
//  nubrick_flutter
//
//  Created by Ryosuke Suzuki on 2024/03/10.
//

import Foundation
import Flutter
import UIKit
@_spi(FlutterBridge) import Nubrick

private func preferredWindow(_ connectedScenes: Set<UIScene>) -> UIWindow? {
    let windowScenes = connectedScenes.compactMap { $0 as? UIWindowScene }
    let preferredStates: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive]

    for state in preferredStates {
        let windows = windowScenes
            .filter { $0.activationState == state }
            .flatMap(\.windows)

        if let keyWindow = windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let visibleWindow = windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
            return visibleWindow
        }
        if let firstWindow = windows.first {
            return firstWindow
        }
    }

    return windowScenes.flatMap(\.windows).first
}

private func topHostViewController(_ viewController: UIViewController?) -> UIViewController? {
    var current = viewController

    while let controller = current {
        if let presented = controller.presentedViewController {
            current = presented
            continue
        }
        if let navigationController = controller as? UINavigationController,
           let visible = navigationController.visibleViewController {
            current = visible
            continue
        }
        if let tabBarController = controller as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            current = selected
            continue
        }
        if let splitViewController = controller as? UISplitViewController,
           let trailing = splitViewController.viewControllers.last {
            current = trailing
            continue
        }
        return controller
    }

    return nil
}

struct EmbeddingEntity {
    let uiview: UIView
    let channel: FlutterMethodChannel
    let accessor: NubrickBridgedViewAccessor?
}

struct RemoteConfigEntity {
    let variant: RemoteConfigVariant?
}

// Flutter's StandardMessageCodec delivers arguments as [String: Any], but the iOS SDK expects
// NubrickArguments ([String: any Sendable]). The cast is ok to do because all codec types
// (String, NSNumber, FlutterStandardTypedData, NSArray, NSDictionary, NSNull) are Sendable.
// Note: Sendable conformance is checked at compile time only, so `as! any Sendable` never fails at runtime.
private func toNubrickArguments(_ args: [String: Any]?) -> NubrickArguments? {
    args?.mapValues { $0 as! any Sendable }
}

private func nubrickSizeToMessage(_ size: NubrickSize) -> [String: Any] {
    switch size {
    case .fixed(let value):
        return [
            "kind": "fixed",
            "value": Double(value),
        ]
    case .fill:
        return [
            "kind": "fill",
        ]
    }
}

@MainActor
class NubrickFlutterManager {
    private var initialized = false
    private var embeddingMaps: [String:EmbeddingEntity]
    private var configMaps: [String:RemoteConfigEntity]

    init() {
        self.embeddingMaps = [:]
        self.configMaps = [:]
    }

    func initialize(
        projectId: String,
        onEvent: (@Sendable (_ event: ComponentEvent) -> Void)? = nil,
        onDispatch: ((_ event: NubrickEvent) -> Void)? = nil,
        onTooltip: ((_ data: String, _ experimentId: String) -> Void)? = nil
    ) {
        NubrickBridge.initialize(
            projectId: projectId,
            onEvent: onEvent,
            onDispatch: onDispatch,
            onTooltip: onTooltip
        )

        if !self.initialized {
            self.initialized = true
            let selectedWindow = preferredWindow(UIApplication.shared.connectedScenes)
            if let vc = topHostViewController(selectedWindow?.rootViewController) {
                let overlay = NubrickSDK.overlayViewController()
                vc.addChild(overlay)
                vc.view.addSubview(overlay.view)
                overlay.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    overlay.view.topAnchor.constraint(equalTo: vc.view.topAnchor),
                    overlay.view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
                    overlay.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
                    overlay.view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
                ])
                overlay.didMove(toParent: vc)
            }
        }
    }

    func getUserId() -> String? {
        return NubrickSDK.getUserId()
    }

    func setUserProperties(properties: [String: Any]) {
        NubrickSDK.setUserProperties(properties)
    }

    func getUserProperties() -> [String: String]? {
        return NubrickSDK.getUserProperties()
    }

    // embedding
    func connectEmbedding(id: String, channelId: String, arguments: [String: Any]?, messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "Nubrick/Embedding/\(channelId)", binaryMessenger: messenger)
        let uiview = NubrickBridge.embeddingForFlutterBridge(id, arguments: toNubrickArguments(arguments), onEvent: { event in
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
                "width": nubrickSizeToMessage(width),
                "height": nubrickSizeToMessage(height),
            ])
        }) { phase in
            switch phase {
            case .completed(let view):
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "completed")
                return view
            case .notFound:
                channel.invokeMethod(EMBEDDING_PHASE_UPDATE_METHOD, arguments: "not-found")
                return UIView()
            case .failed(_):
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
    func connectRemoteConfig(id: String, channelId: String, onPhase:  @escaping (@Sendable (RemoteConfigPhase) -> Void)) {
        let entity = RemoteConfigEntity(variant: nil)
        self.configMaps[channelId] = entity

        NubrickSDK.remoteConfig(id) { [weak self] phase in
            Task { @MainActor in
                guard let self else { return }
                switch phase {
                case .completed(let config):
                    if self.configMaps[channelId] == nil {
                        return
                    }
                    let entity = RemoteConfigEntity(variant: config)
                    self.configMaps[channelId] = entity
                    onPhase(phase)
                case .notFound:
                    onPhase(phase)
                case .failed(_):
                    onPhase(phase)
                case .loading:
                    break
                }
            }
        }
    }

    func disconnectRemoteConfig(channelId: String) {
        self.configMaps[channelId] = nil
    }

    func connectEmbeddingInRemoteConfigValue(key: String, channelId: String, arguments: [String: Any]?, embeddingChannelId: String, messenger: FlutterBinaryMessenger) {
        guard let entity = self.configMaps[channelId] else {
            return
        }
        guard let variant = entity.variant else {
            return
        }
        let channel = FlutterMethodChannel(name: "Nubrick/Embedding/\(embeddingChannelId)", binaryMessenger: messenger)
        guard let uiview = variant.getAsUIView(key, arguments: toNubrickArguments(arguments), onEvent: { event in
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
            case .failed(_):
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
    func connectTooltipEmbedding(channelId: String, rootBlock: String, messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "Nubrick/Embedding/\(channelId)", binaryMessenger: messenger)
        let accessor = NubrickBridge.renderUIView(
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
            try accessor.dispatchAction(event)
        } catch {}
    }

    func disconnectTooltipEmbedding(channelId: String) {
        self.embeddingMaps[channelId] = nil
    }

    func appendTooltipExperimentHistory(experimentId: String) {
        guard !experimentId.isEmpty else {
            return
        }
        NubrickSDK.appendTooltipExperimentHistory(experimentId: experimentId)
    }

    // trigger
    func dispatch(name: String) {
        NubrickSDK.dispatch(NubrickEvent(name))
    }

    /**
     * Sends crash events from Flutter.
     *
     * This method constructs a crash event and forwards it to the Nubrick SDK for crash reporting
     * with platform set to "flutter".
     *
     * - Parameter exceptionsList: List of exception records from Flutter
     * - Parameter flutterSdkVersion: The Flutter SDK version
     * - Parameter severity: The severity level ("crash" or "warning")
     */
    func sendFlutterCrash(_ exceptionsList: [[String: Any?]], flutterSdkVersion: String?, severity: String?) {
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
            NubrickSDK.sendFlutterCrash(crashEvent)
        }
    }
}
