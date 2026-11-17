import UIKit
import simd

// Parameter adapter for the already-shipped Clear material. No frame capture,
// renderer, display link or original SystemBox code is instantiated here.
@objc(NGDockMaterialParameters)
final class NGDockMaterialParameters: NSObject {
    private var configuration = TheseusConfiguration.clear
    private var size: CGSize = .zero
    private var drawPadding: CGPoint { .zero }
    private var isTintDimmed: Bool { false }
    private var shaderCornerRadius: CGFloat { -configuration.shape.cornerRadius }
    private func bodyCurveKnots(_ quad: Int) -> SIMD4<Float> {
        guard let c = configuration.theme.bodyCurve, c.count == 16 else { return .zero }
        return SIMD4(Float(c[quad*4]), Float(c[quad*4+1]), Float(c[quad*4+2]), Float(c[quad*4+3]))
    }
    @objc(packetWithSize:radius:scale:dark:)
    func packet(size: CGSize, radius: CGFloat, scale: CGFloat, dark isDark: Bool) -> NSDictionary {
        self.size = size
        configuration = .clear
        configuration.glassRim?.bandBias = 0 // existing Dock-only setting from 0.1.3
        configuration.shape.cornerRadius = min(max(radius, 0.01), min(size.width,size.height)/2)
        configuration.shape.padding = .zero
        configuration.shape.widthInset = 0
        configuration.shape.heightInset = 0
        configuration.shape.continuousCapsule = configuration.shape.cornerRadius >= min(size.width,size.height)/2-0.5
        let viewSize = SIMD2<Float>(Float(ceil(size.width*scale)), Float(ceil(size.height*scale)))
        let padding = CGPoint.zero
        let refractionPadding = SIMD2<Float>.zero
        var tintR: CGFloat = 0, tintG: CGFloat = 0, tintB: CGFloat = 0, tintA: CGFloat = 0
        configuration.theme.tintColor.getRed(&tintR, green: &tintG, blue: &tintB, alpha: &tintA)

        let spectrum = min(max(TheseusSettings.shared.tintSpectrum, 0.0), 1.0)

        // Branch on colour alpha x intensity, not alpha alone: zero intensity
        // falls back to the neutral body, not to a third state.
        tintA *= min(max(configuration.theme.tintOpacity, 0.0), 1.0)

        let isDarkAppearance = isDark
        let luminanceLift = TheseusMaterialModel.liftAmount(configuration: configuration)
        let transfer = TheseusMaterialModel.bodyTransfer(
            configuration: configuration,
            isDark: isDarkAppearance,
            spectrum: spectrum,
            style: TheseusSettings.shared.effectiveGlassStyle
        )
        let bodyParams = SIMD4<Float>(
            Float(transfer.poleMix),
            Float(transfer.toneStrength),
            Float(TheseusMaterialModel.gain(configuration: configuration)),
            Float(TheseusMaterialModel.chromaScale(configuration: configuration, isDark: isDarkAppearance, spectrum: spectrum))
        )
        let bodyPole = Float(transfer.pole)

        if isTintDimmed {
            let gray = 0.299 * tintR + 0.587 * tintG + 0.114 * tintB
            tintR = gray
            tintG = gray
            tintB = gray
        }
        let tintModel = TheseusMaterialModel.tintModel(isDark: isDarkAppearance)
        let glassStyle = TheseusSettings.shared.effectiveGlassStyle
        let glassAmount = TheseusConfiguration.GlassRim.frostAmount(spectrum: spectrum, style: glassStyle)
        let styledRim = configuration.glassRim?.styled(glassStyle)
        let glassFace = configuration.glassRim?.face(isDark: isDarkAppearance, tintAmount: spectrum, style: glassStyle)
        let glassTint = configuration.glassRim.map { _ in
            TheseusConfiguration.GlassRim.tintMatrix(red: tintR, green: tintG, blue: tintB, isDark: isDarkAppearance)
        }

        var specFarR: CGFloat = 0, specFarG: CGFloat = 0, specFarB: CGFloat = 0, specFarA: CGFloat = 0
        configuration.edgeEffects.farColor.getRed(&specFarR, green: &specFarG, blue: &specFarB, alpha: &specFarA)

        var specNearR: CGFloat = 0, specNearG: CGFloat = 0, specNearB: CGFloat = 0, specNearA: CGFloat = 0
        configuration.edgeEffects.nearColor.getRed(&specNearR, green: &specNearG, blue: &specNearB, alpha: &specNearA)

        let mergeShapeCount = 0

        let lensProfile = configuration.refraction.lensProfile
        let fillColor = LensMorph.sRGBComponents(configuration.lensFillColor.cgColor).map { $0.map(Float.init) } ?? [1, 1, 1, 1]
        var refractionUniforms = GlassParams(
            viewSize: viewSize,
            cornerRadius: Float(shaderCornerRadius * scale),
            opacity: Float(configuration.opacity),
            edgeWidth: Float(configuration.refraction.edgeWidth * scale),
            iorFactor: Float(configuration.refraction.intensity),
            luminanceLift: Float(luminanceLift),
            rimGlow: Float(configuration.edgeEffects.rimGlow),
            lensRiseStart: Float(lensProfile.riseStart),
            lensRiseEnd: Float(lensProfile.riseEnd),
            specularIntensity: Float(configuration.edgeEffects.glareIntensity),
            specularFocus: Float(configuration.edgeEffects.glareFocus),
            lensFrost: Float(lensProfile.frost),
            lensContour: Float(isDarkAppearance ? lensProfile.contourDarkening : lensProfile.contourDarkeningLight),
            oppositeFalloff: Float(configuration.edgeEffects.oppositeFalloff),
            chromaticSpread: Float(configuration.refraction.dispersion),
            mirrorMode: configuration.refraction.reflective ? 1.0 : 0.0,
            bodyPole: bodyPole,
            stretchScale: SIMD2<Float>(
                Float(configuration.morph.scale.x),
                Float(configuration.morph.scale.y)
            ),
            shapePadding: refractionPadding,
            interiorSharpness: Float(min(max(configuration.refraction.interiorSharpness, 0.0), 1.0)),
            magCenterY: Float(configuration.refraction.magnificationCenterY * scale),
            tint: SIMD4<Float>(Float(tintR), Float(tintG), Float(tintB), Float(tintA)),
            farSpecularColor: SIMD4<Float>(Float(specFarR), Float(specFarG), Float(specFarB), Float(specFarA)),
            nearSpecularColor: SIMD4<Float>(Float(specNearR), Float(specNearG), Float(specNearB), Float(specNearA)),
            tintWeights: SIMD4<Float>(
                Float(min(max(configuration.theme.surfaceTintWeight, 0.0), 1.0)),
                Float(min(max(configuration.theme.edgeTintWeight, 0.0), 1.0)),
                Float(min(max(configuration.theme.highlightTintPreservation, 0.0), 1.0)),
                Float(min(max(configuration.theme.edgeIridescence, 0.0), 1.0))
            ),
            mergeParams: SIMD4<Float>(
                Float(mergeShapeCount),
                Float(configuration.shape.mergeSmoothing * scale),
                Float(max(configuration.refraction.magnification, 0.25)),
                Float(max(configuration.refraction.thickness, 1.0) * scale)
            ),
            lensLight: SIMD4<Float>(
                Float(isDarkAppearance ? lensProfile.highlight : lensProfile.highlightLight),
                Float(lensProfile.highlightSide),
                Float(lensProfile.highlightWidth),
                Float(isDarkAppearance ? lensProfile.highlightFade : lensProfile.highlightFadeLight)
            ),
            lensFall: SIMD4<Float>(
                Float(lensProfile.fallStart),
                Float(lensProfile.fallLength),
                Float(isDarkAppearance ? lensProfile.shadeDark : lensProfile.shade),
                Float(lensProfile.shadeReach * scale)
            ),
            bodyParams: bodyParams,
            tintParams: SIMD4<Float>(
                Float(tintModel.threshold),
                Float(tintModel.pole),
                configuration.shape.continuousCapsule ? 1 : 0,
                Float(isDarkAppearance ? lensProfile.highlightBottomDark : lensProfile.highlightBottom)
            ),
            lensRim: SIMD4<Float>(
                Float(isDarkAppearance ? lensProfile.contourSideDark : lensProfile.contourSide),
                Float(isDarkAppearance ? lensProfile.shadeSideDark : lensProfile.shadeSide),
                Float(lensProfile.shadeSideOnset),
                Float(isDarkAppearance ? lensProfile.shadeOnsetDark : lensProfile.shadeOnset)
            ),
            lensRim2: SIMD4<Float>(
                Float(isDarkAppearance ? lensProfile.shadeFloorDark : lensProfile.shadeFloor),
                Float(lensProfile.lip * scale),
                Float(lensProfile.lipReach * scale),
                Float(isDarkAppearance ? lensProfile.highlightTailDark : lensProfile.highlightTail)
            ),
            lensRim3: SIMD4<Float>(
                Float(isDarkAppearance ? lensProfile.contourRampDark : lensProfile.contourRamp),
                Float(isDarkAppearance ? lensProfile.contourSideWidthDark : lensProfile.contourSideWidth),
                Float((isDarkAppearance && lensProfile.shadeSideReachDark > 0 ? lensProfile.shadeSideReachDark : lensProfile.shadeSideReach) * scale),
                Float(lensProfile.shadeShoulder)
            ),
            lensRim4: SIMD4<Float>(
                Float(lensProfile.shadeSideShoulder),
                Float(lensProfile.shadeLobeTilt),
                Float(!isDarkAppearance && lensProfile.highlightLobeLight > 0 ? lensProfile.highlightLobeLight : lensProfile.highlightLobe),
                Float(lensProfile.shadeSideOnsetWidth)
            ),
            lensRim5: SIMD4<Float>(
                Float(isDarkAppearance ? lensProfile.contourChromaDark : lensProfile.contourChroma),
                Float(lensProfile.capExponent),
                Float(isDarkAppearance ? lensProfile.contourFlatDark : lensProfile.contourFlat),
                Float(lensProfile.capExponentTip)
            ),
            lensRim6: SIMD4<Float>(Float(configuration.lensFill), Float(configuration.lensRimScale), Float(configuration.refraction.rimDispersion * scale), Float(configuration.refraction.rimDispersionDepth * scale)),
            lensRim7: SIMD4<Float>(fillColor[0], fillColor[1], fillColor[2], 0),
            lensRim8: SIMD4<Float>(Float(configuration.lensShadowOpacity), Float(configuration.lensShadowOffset * scale), Float(configuration.lensShadowRadius * scale), Float(lensProfile.shadeTopLobeShift)),
            lensRim9: SIMD4<Float>(Float(lensProfile.shadeCapOnsetShare), Float(lensProfile.shadeTopExponent), Float(lensProfile.shadeSideExponent), lensProfile.highlightInLinearLight ? 1 : 0),
            shapeEdge: SIMD4<Float>(Float(configuration.outerGlow), Float(configuration.edgeFeather * scale), Float(configuration.lensRefractionScale), lensProfile.capOutlineOnly ? 1 : 0),
            chainWarp: configuration.lensChain.map { SIMD4<Float>(Float($0.backdropWarp * scale), Float($0.backdropWarpHeight * scale), Float($0.inset * scale), $0.warpIgnoresShare ? 1 : 0) } ?? .zero,
            chainItems: configuration.lensChain.map { SIMD4<Float>(Float($0.itemWarp * scale), Float($0.itemLensing * scale), Float($0.itemWarpHeight * scale), Float($0.ovalization)) } ?? .zero,
            chainSplit: configuration.lensChain.map { SIMD4<Float>(Float($0.aberration * scale), Float($0.aberrationBand * scale), Float($0.aberrationFade * scale), $0.detailBlurred ? 2 : 1) } ?? .zero,
            chainInner: configuration.lensChain.map { chain in
                let side = min(CGFloat(viewSize.x) / scale - 2 * padding.x, CGFloat(viewSize.y) / scale - 2 * padding.y)
                let inner = chain.innerRefractionPerSide > 0 ? min(chain.innerRefractionPerSide * side, chain.innerRefractionCap > 0 ? chain.innerRefractionCap : .greatestFiniteMagnitude) : chain.innerRefraction
                let innerHeight = chain.innerHeightPerSide > 0 ? min(chain.innerHeightPerSide * side, chain.innerHeightCap) : chain.innerRefractionHeight
                let refraction = styledRim?.innerRefraction(shortSide: side) ?? (inner, innerHeight)
                return SIMD4<Float>(Float(refraction.amount * scale), Float(refraction.height * scale), Float(min(max(chain.frost, 0), 1)), Float(max(chain.itemRimFade, 0) * scale))
            } ?? .zero,
            tintModel: SIMD4<Float>(
                Float(tintModel.gain),
                Float(tintModel.offset),
                Float(tintModel.closing),
                Float(tintModel.toPole)
            ),
            glassRim: styledRim.map { rim in
                SIMD4<Float>(rim.generation == .iOS26 ? 2 : 1, Float(isDarkAppearance ? rim.bandSpreadDark : rim.bandSpreadLight), Float(rim.bandOvalization), Float(rim.bandBias))
            } ?? .zero,
            glassShadow: styledRim.map { rim in
                let shortSide = min(CGFloat(viewSize.x) / scale - 2 * padding.x, CGFloat(viewSize.y) / scale - 2 * padding.y)
                return SIMD4<Float>(
                    Float(rim.ringShadowOpacity),
                    Float(rim.dropShadowAmount(isDark: isDarkAppearance, shortSide: shortSide)),
                    Float(rim.shadowSigma(shortSide: shortSide) * scale),
                    Float(TheseusConfiguration.GlassRim.dropShadowOffset * scale)
                )
            } ?? .zero,
            glassHighlight: styledRim.map { rim in
                let matrix = rim.highlight(isDark: isDarkAppearance)
                return SIMD4<Float>(matrix.x, matrix.y, matrix.z, isDarkAppearance || rim.generation == .iOS26 ? 0 : 1)
            } ?? .zero,
            glassScale: SIMD4<Float>(Float(scale), Float((styledRim?.outerRefractionFullDepth ?? 0) * scale), 0, 0),
            glassBlur: styledRim.map { rim in
                let frost = rim.frost(tintAmount: glassAmount)
                return SIMD4<Float>(Float(frost.blend), Float(frost.cover), isDarkAppearance ? 1 : 0, 1)
            } ?? .zero,
            glassBlurOpacity: styledRim.map { rim in
                let shortSide = min(CGFloat(viewSize.x) / scale - 2 * padding.x, CGFloat(viewSize.y) / scale - 2 * padding.y)
                return SIMD4<Float>(Float(rim.blurRadiusDeep), Float(rim.blurRadiusNearRim), Float(rim.blurRadiusAtRim), Float(shortSide / 2 * scale))
            } ?? .zero,
            glassBlurSigma: styledRim.map { rim in
                SIMD4<Float>(
                    Float(rim.blurSigma(tintAmount: glassAmount) * scale),
                    Float(TheseusConfiguration.GlassRim.blurSoftness * scale),
                    Float(rim.detailSigma(tintAmount: glassAmount) * scale),
                    Float(rim.coarseSigma(tintAmount: glassAmount) * scale)
                )
            } ?? .zero,
            glassFace: glassFace.map { SIMD4<Float>(Float($0.black), Float($0.white), Float($0.saturation), Float($0.maxLuma)) } ?? .zero,
            glassFaceFill: glassFace?.fill ?? .zero,
            glassOuter: styledRim.map { rim in
                let shortSide = min(CGFloat(viewSize.x) / scale - 2 * padding.x, CGFloat(viewSize.y) / scale - 2 * padding.y)
                let outer = rim.outerRefraction(shortSide: shortSide)
                return SIMD4<Float>(Float(outer.amount * scale), Float(outer.height * scale), Float(rim.outerRefractionShare), Float(scale))
            } ?? .zero,
            glassTintRed: glassTint?.red ?? .zero,
            glassTintGreen: glassTint?.green ?? .zero,
            glassTintBlue: glassTint?.blue ?? .zero,
            bodyCurve0: bodyCurveKnots(0),
            bodyCurve1: bodyCurveKnots(1),
            bodyCurve2: bodyCurveKnots(2),
            bodyCurve3: bodyCurveKnots(3),
            bodyCurveInfo: SIMD4<Float>(configuration.theme.bodyCurve?.count == 16 ? 1 : 0, Float(configuration.theme.bodyCurveChromaSlope), Float(configuration.theme.bodyCurveSaturation), 0)
        )
        let lensLift = applyNativeLens(configuration.nativeLens, to: &refractionUniforms, scale: scale)
        applyFlexGlow(configuration.flexGlow, to: &refractionUniforms, scale: scale)
        refractionUniforms.lens26ShadowOffset.z = Float(configuration.shapeOffset.x * scale)
        refractionUniforms.lens26ShadowOffset.w = Float(configuration.shapeOffset.y * scale)
        if let chain = configuration.lensChain {
            refractionUniforms.lens26Items.x = Float((chain.itemLensingHeight > 0 ? chain.itemLensingHeight : chain.itemWarpHeight) * scale) * lensLift
        }


        let rim = configuration.glassRim?.styled(TheseusSettings.shared.effectiveGlassStyle)
        let amount = TheseusConfiguration.GlassRim.frostAmount(spectrum: TheseusSettings.shared.tintSpectrum, style: TheseusSettings.shared.effectiveGlassStyle)
        let fine = rim?.detailSigma(tintAmount: amount) ?? configuration.effectiveSigma
        let coarse = rim?.coarseSigma(tintAmount: amount) ?? fine
        let fill = rim?.fillSigma ?? fine
        let bytes = withUnsafeBytes(of: &refractionUniforms) { Data($0) }
        return ["uniforms":bytes, "fineSigma":fine, "coarseSigma":coarse,
                "fillSigma":fill, "width":size.width, "height":size.height,
                "scale":scale, "style":0, "dark":isDark]
    }
    private func applyFlexGlow(_ glow: FlexGlow?, to uniforms: inout GlassParams, scale: CGFloat) {
        guard let glow, glow.amount > 0 || glow.spotAmount > 0 else { return }
        let s = Float(scale)
        uniforms.flexGlow = SIMD4(Float(glow.amount), Float(glow.spotAmount * FlexGlow.spotPeak), Float(FlexGlow.spotWidth * glow.spotRadius) * s, 0)
        let padding = drawPadding
        uniforms.flexGlowCenter = SIMD4(Float((glow.spotCenter.x + padding.x) * scale), Float((glow.spotCenter.y + padding.y) * scale), 0, 0)
        uniforms.flexBigRed = FlexGlow.matrix[0]
        uniforms.flexBigGreen = FlexGlow.matrix[1]
        uniforms.flexBigBlue = FlexGlow.matrix[2]
    }

    @discardableResult
    private func applyNativeLens(_ lens: NativeLens26?, to uniforms: inout GlassParams, scale: CGFloat) -> Float {
        guard let lens else { return 1 }
        var transform: Float = 1
        if lens.baseHeight > 0 {
            let visible = (uniforms.viewSize.y - 2 * uniforms.shapePadding.y) * uniforms.stretchScale.y / Float(scale)
            transform = visible / Float(lens.baseHeight)
            uniforms.chainWarp.x *= transform
            uniforms.chainWarp.y *= transform
            uniforms.chainItems.x *= transform
            uniforms.chainItems.y *= transform
            uniforms.chainItems.z *= transform
            uniforms.chainInner.x *= transform
            uniforms.chainInner.y *= transform
        }
        uniforms.lens26 = SIMD4(1, Float(scale), Float(lens.faceBlack), Float(lens.faceWhite))
        uniforms.lens26Face = SIMD4(Float(lens.faceSaturation), Float(lens.holdingWhite), Float(lens.holdingStart), Float(lens.holdingEnd))
        uniforms.lens26BlurDistance = lens.blurDistances
        uniforms.lens26BlurOpacity = lens.blurOpacities
        uniforms.lens26Blur = SIMD4(Float(lens.blurRadius * 1.6), Float(lens.innerShadowOpacity), Float(lens.innerShadowRadius) * transform, Float(lens.innerShadowOffset) * transform)
        let aberrationScale = lens.baseHeight > 0 ? (uniforms.viewSize.y - 2 * uniforms.shapePadding.y) * uniforms.stretchScale.y / Float(scale) / Float(lens.baseHeight) : 1
        uniforms.lens26Aberration = SIMD4(Float(lens.aberration) * aberrationScale, Float(lens.aberrationOffset), Float(lens.edgeStart), Float(lens.edgeEnd))
        uniforms.lens26AberrationAngle = SIMD4(Float(cos(lens.aberrationAngle)), Float(sin(lens.aberrationAngle)), Float(lens.shadowFaceOpacity), Float(lens.shadowOpacity))
        uniforms.lens26Shadow = SIMD4(lens.shadowFill.x, lens.shadowFill.y, lens.shadowFill.z, Float(lens.shadowRadius))
        let lights = Array(lens.highlights.prefix(2))
        uniforms.lens26ShadowOffset = SIMD4(Float(lens.shadowOffset), Float(lights.count), 0, 0)
        var line = SIMD4<Float>.zero
        for (index, light) in lights.enumerated() {
            let key = SIMD4(light.key.x, light.key.y, Float(cos(light.spread)), light.remap)
            let rows = light.matrix + Array(repeating: SIMD4<Float>.zero, count: max(0, 3 - light.matrix.count))
            if index == 0 {
                uniforms.lens26Key0 = key
                uniforms.lens26Red0 = rows[0]
                uniforms.lens26Green0 = rows[1]
                uniforms.lens26Blue0 = rows[2]
                line.x = Float(light.curvature)
                line.y = Float(light.height)
            } else {
                uniforms.lens26Key1 = key
                uniforms.lens26Red1 = rows[0]
                uniforms.lens26Green1 = rows[1]
                uniforms.lens26Blue1 = rows[2]
                line.z = Float(light.curvature)
                line.w = Float(light.height)
            }
        }
        uniforms.lens26Line = line
        return transform
    }

}
