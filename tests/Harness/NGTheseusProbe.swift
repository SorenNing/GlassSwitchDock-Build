import UIKit
import Metal

// Compiled in the same GlassSwitchDock module as the untouched vendor Swift.
// Read-only introspection plus vendor-supplied scriptedTouch entry points.
@objc(NGTheseusProbe)
final class NGTheseusProbe: NSObject {
    @objc static func inspectSwitch(_ view: UIView) -> NSDictionary {
        guard let control = view as? TheseusSwitch else { return ["error": "not original TheseusSwitch"] }
        let fresh = TheseusSwitch(frame: CGRect(x: 0, y: 0, width: 63, height: 28))
        return ["class": NSStringFromClass(type(of: control)),
                "isOn": control.isOn,
                "layout": String(reflecting: control.layout),
                "defaultLayout": String(reflecting: fresh.layout),
                "layoutUnmodified": String(reflecting: control.layout) == String(reflecting: fresh.layout),
                "materialUnmodified": control.glassMaterial == fresh.glassMaterial,
                "onTintUnmodified": control.onTintColor.isEqual(fresh.onTintColor),
                "offTintUnmodified": control.offTintColor.isEqual(fresh.offTintColor),
                "thumbTintUnmodified": control.thumbTintColor.isEqual(fresh.thumbTintColor),
                "width": control.bounds.width, "height": control.bounds.height,
                "intrinsicWidth": control.intrinsicContentSize.width,
                "intrinsicHeight": control.intrinsicContentSize.height]
    }

    @objc static func inspectClear(_ view: UIView) -> NSDictionary {
        guard let glass = view as? TheseusView else { return ["error": "not original TheseusView"] }
        let original = TheseusConfiguration.clear
        var expected = original
        expected.glassRim?.bandBias = 0 // The single, explicitly requested Dock edge change.
        // Everything equals the real preset except the documented side-band
        // bias. Geometry and the single edge adjustment are asserted separately.
        func fingerprint(_ value: Any) -> String {
            let mirror = Mirror(reflecting: value)
            if let color = value as? UIColor {
                let resolved = color.resolvedColor(with: glass.traitCollection)
                return String(describing: resolved.cgColor.components ?? [])
            }
            if mirror.children.isEmpty { return String(reflecting: value) }
            return mirror.children.map { "\($0.label ?? "_")=\(fingerprint($0.value))" }.joined(separator: ";")
        }
        func optics(_ value: TheseusConfiguration) -> [String: String] {
            var result: [String: String] = [:]
            for child in Mirror(reflecting: value).children {
                guard let key = child.label else { continue }
                if key == "shape" {
                    // Only corner radius/width/height geometry may be container-derived.
                    for field in Mirror(reflecting: child.value).children {
                        guard let label = field.label, !["cornerRadius", "continuousCapsule", "padding", "widthInset", "heightInset"].contains(label) else { continue }
                        result["shape." + label] = fingerprint(field.value)
                    }
                } else if key != "captureMethod" { result[key] = fingerprint(child.value) }
            }
            return result
        }
        let actual = optics(glass.configuration), reference = optics(expected)
        let mismatches = Set(actual.keys).union(reference.keys).sorted().filter { actual[$0] != reference[$0] }
        var fields: [String: Any] = ["class": NSStringFromClass(type(of: glass)),
                                   "matchesClearExceptSideBandBias": mismatches.isEmpty,
                                   "originalBandBias": original.glassRim?.bandBias ?? -999,
                                   "dockBandBias": glass.configuration.glassRim?.bandBias ?? -999,
                                   "mismatches": mismatches, "actual": actual, "expected": reference,
                                   "isRendering": glass.isRendering,
                                   "captureMethod": String(describing: glass.configuration.captureMethod),
                                   "captureBackendExpected": String(describing: TheseusCapability.isDeviceSupported ? CaptureMethod.layerRendering : CaptureMethod.surfaceBased),
                                   "cornerRadius": glass.configuration.shape.cornerRadius,
                                   "continuousCapsule": glass.configuration.shape.continuousCapsule,
                                   "snapshotReady": glass.captureSnapshot != nil,
                                   "fallbackActive": false, "rendererPresent": false]
        // Observe private backend state without changing render settings.
        var hierarchy: Mirror? = Mirror(reflecting: glass)
        while let mirror = hierarchy {
            for child in mirror.children {
                if child.label == "isUsingFallback", let value = child.value as? Bool { fields["fallbackActive"] = value }
                if child.label == "renderer" { fields["rendererPresent"] = !Mirror(reflecting: child.value).children.isEmpty }
            }
            hierarchy = mirror.superclassMirror
        }
        return fields as NSDictionary
    }

    @objc static func snapshot(_ view: UIView, path: String) -> NSDictionary {
        guard let glass = view as? TheseusView, let image = glass.captureSnapshot,
              let data = image.dataProvider?.data else { return ["ready": false] }
        let bytes = data as Data
        let hash = bytes.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        var wrote = false
        if let png = UIImage(cgImage: image).pngData() {
            do { try png.write(to: URL(fileURLWithPath: path), options: .atomic); wrote = true }
            catch { wrote = false }
        }
        return ["ready": true, "checksum": String(hash), "bytes": bytes.count,
                "width": image.width, "height": image.height, "wrotePNG": wrote]
    }

    @objc static func activate(_ view: UIView) -> Bool {
        guard let control = view as? TheseusSwitch else { return false }
        return control.accessibilityActivate()
    }

    @objc static func drag(_ view: UIView, toOn: Bool) -> Bool {
        guard let control = view as? TheseusSwitch else { return false }
        let start = CGPoint(x: control.isOn ? 43 : 20, y: 14)
        control.scriptedTouchBegan(at: start)
        control.scriptedTouchMoved(to: CGPoint(x: toOn ? 62 : 1, y: 14))
        control.scriptedTouchEnded()
        return true
    }

    @objc static func settings() -> NSDictionary {
        let settings = TheseusSettings.shared
        return ["glassStyle": String(describing: settings.glassStyle),
                "iosVersionOverride": settings.iosVersionOverride as Any? ?? NSNull(),
                "tierOverride": settings.tierOverride.map { String(describing: $0) } as Any? ?? NSNull(),
                "refractionPolicyOverride": settings.refractionPolicyOverride.map { String(describing: $0) } as Any? ?? NSNull(),
                "refractionQualityOverride": settings.refractionQualityOverride.map { String(describing: $0) } as Any? ?? NSNull(),
                "followsSystemTint": settings.followsSystemTint,
                "respectsReduceMotion": settings.respectsReduceMotion,
                "respectsReduceTransparency": settings.respectsReduceTransparency]
    }
}
