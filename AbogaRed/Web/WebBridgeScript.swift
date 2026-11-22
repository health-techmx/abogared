import Foundation
import WebKit

enum WebBridgeScript {
    static let handlerName = "abogaredBridge"

    static func makeUserScript(initialPermission: String) -> WKUserScript {
        let safeStatus = ["granted", "denied", "default"].contains(initialPermission) ? initialPermission : "default"
        let source = #"""
        (function() {
            if (window.AbogaRedIOS) return;

            var ALLOWED_ORIGIN = 'https://abogared.health-tech.com.mx';
            window.__abogaredIOSPermission = '__INITIAL_PERMISSION__';

            function post(action, data) {
                if (window.location.origin !== ALLOWED_ORIGIN) return false;
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.abogaredBridge) {
                        window.webkit.messageHandlers.abogaredBridge.postMessage({
                            action: action,
                            data: data || {}
                        });
                        return true;
                    }
                } catch (e) {}
                return false;
            }

            window.__abogaredSetIOSPermission = function(status) {
                var clean = (status === 'granted' || status === 'denied') ? status : 'default';
                window.__abogaredIOSPermission = clean;
                try {
                    window.dispatchEvent(new CustomEvent('abogared-notification-permission', {
                        detail: { status: clean }
                    }));
                } catch (e) {}
            };

            window.AbogaRedIOS = {
                isNativeApp: function() { return true; },
                getPlatform: function() { return 'ios_swift'; },
                getAppVersion: function() { return '1.2'; },
                getPermissionStatus: function() {
                    return window.__abogaredIOSPermission || 'default';
                },
                requestPermission: function() {
                    post('requestPermission');
                },
                showNotification: function(id, notifyKey, title, body, url, urgent) {
                    post('showNotification', {
                        id: String(id || ''),
                        notifyKey: String(notifyKey || ''),
                        title: String(title || ''),
                        body: String(body || ''),
                        url: String(url || '/calendario'),
                        urgent: Boolean(urgent)
                    });
                },
                showTestNotification: function(title, body, url) {
                    post('showTestNotification', {
                        title: String(title || ''),
                        body: String(body || ''),
                        url: String(url || '/calendario')
                    });
                },
                syncAlertToken: function(token, baseUrl) {
                    post('syncAlertToken', {
                        token: String(token || ''),
                        baseUrl: String(baseUrl || ALLOWED_ORIGIN)
                    });
                },
                clearAlertToken: function() {
                    post('clearAlertToken');
                }
            };
        })();
        """#.replacingOccurrences(of: "__INITIAL_PERMISSION__", with: safeStatus)

        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}
