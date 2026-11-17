#pragma once
#include <simd/simd.h>
struct NGTheseusParams {
    vector_float2 viewSize;
    float cornerRadius;
    float opacity;
    float edgeWidth;      // refraction edge thickness, px
    float iorFactor;
    float luminanceLift;  // additive, 0...1
    float rimGlow;
    float lensRiseStart;  // bevel rise start, fraction of the band from the rim
    float lensRiseEnd;    // bevel plateau reached, fraction of the band
    float specularIntensity;
    float specularFocus;
    float lensFrost;      // blurred mix at the bevel peak
    float lensContour;    // contour darkening, 0 = none
    float oppositeFalloff;
    float chromaticSpread;
    float mirrorMode;     // 0 = lens, 1 = mirror
    float bodyPole;       // luminance the body mixes toward by bodyParams.x
    vector_float2 stretchScale;
    vector_float2 shapePadding;  // inset from the edges
    float interiorSharpness; // 0 = blurred backdrop, 1 = sharp source
    float magCenterY;     // loupe centre offset, scaled px, +y down
    vector_float4 tint;
    vector_float4 farSpecularColor;
    vector_float4 nearSpecularColor;
    // x surface tint, y edge tint, z highlight tint preservation, w edge iridescence
    vector_float4 tintWeights;
    // x merged shape count, y merge smoothing px, z interior loupe magnification (1 = none), w slab thickness px
    vector_float4 mergeParams;
    // x lens highlight strength, y side factor, z width px, w fade px
    vector_float4 lensLight;
    // x plateau end and y tail length (fractions of the band), z rim shade strength, w shade reach px
    vector_float4 lensFall;
    // x body mix toward bodyPole after the tone, y dark tone strength, z backdrop gain, w chroma scale
    vector_float4 bodyParams;
    // x body luminance past which a dark tint fades, y the grey it fades toward,
    // z continuous capsule ends (1) or circular (0), w bottom rim highlight share
    vector_float4 tintParams;
    // x contour factor on the sides, y side shade factor, z side shade onset px, w top shade onset px
    vector_float4 lensRim;
    // x shade floor inside the rim, y rim lip px, z lip fade px, w rim line tail strength
    vector_float4 lensRim2;
    // x contour ramp px (0 = 2 px box), y extra side contour px, z side shade reach px (0 = lensFall.w),
    // w shade shoulder as a share of the reach (0 = linear)
    vector_float4 lensRim3;
    // x side shade shoulder (< 0 = lensRim3.w), y side lobe tilt in deg below the horizontal (0 = single-lobe shade),
    // z rim line lobe exponent (0 = 4th power, flat tail), w side shade onset px, ending at lensRim.z
    vector_float4 lensRim4;
    // x contour chroma kept (0 = multiplicative, 1 = luminance only), y superellipse exponent on the vertical axis
    // (0 = stadium), z flat share of the contour drop, w the exponent at the side tips
    vector_float4 lensRim5;
    // x fill toward lensRim7 (0 = glass, 1 = solid), y rim scale on bevel, frost, shade, contour and line (< 0 = 1 - x)
    vector_float4 lensRim6;
    // xyz the fill colour
    vector_float4 lensRim7;
    // xyz the lens drop shadow (opacity, offset px, radius px), w top shade lobe reach below the horizontal
    vector_float4 lensRim8;
    // x top shade onset share on the sides, y top lobe exponent, z side lobe exponent,
    // w rim line in linear light (1) or encoded (0)
    vector_float4 lensRim9;
    // x outer glow (< 0 = OUTER_GLOW_STRENGTH), y edge feather px (0 = hard), z refraction and rim dispersion share,
    // w superellipse outline only (1): shade and refraction follow the stadium
    vector_float4 shapeEdge;
    // px: x backdrop warp, y its height, z frame inset inside the drawn outline,
    // w warp taken as is (1) or scaled by the refraction share (0)
    vector_float4 chainWarp;
    // x item warp, y item lensing, z their height, w gradient ovalisation
    vector_float4 chainItems;
    // x aberration (half the red-to-blue spread), y its depth, z fade depth,
    // w off (0), on (1), on with the blurred capture's detail (2)
    vector_float4 chainSplit;
    // x inner refraction px (inward at the rim), y its height, z blurred share of the warped backdrop,
    // w item fade-in depth from the rim
    vector_float4 chainInner;
    // Brand tint: x gain and y offset per unit of body shortfall from white; z channel closing
    // and w move toward tintParams.y per unit of body luminance past tintParams.x
    vector_float4 tintModel;
    // UIGlassEffect's rim: x on (1) / off (0), y light band spread outside the frame (radians),
    // z gradient ovalisation, w colour bias
    vector_float4 glassRim;
    // x ring shadow opacity, y drop shadow opacity, z drop shadow sigma px, w drop shadow offset px
    vector_float4 glassShadow;
    // Highlight vibrancy: x brightness, y saturation, z offset; w tint covers the outer band (1) or stops at the frame (0)
    vector_float4 glassHighlight;
    // x pixels per point
    vector_float4 glassScale;
    // Frost: x how far the fill lightens (light) or darkens (dark) what lies under it, y fill cover share,
    // z darken (1) or lighten (0), w coarse blur bound (1)
    vector_float4 glassBlur;
    // Blur radius share: x deep inside (from w px in), y 1 pt inside, z at the frame
    vector_float4 glassBlurOpacity;
    // px: x full blur the shares scale, y capture softness, z detail blur, w coarse blur
    vector_float4 glassBlurSigma;
    // Face colour matrix: x black, y white, z saturation, w luminance cap; glassFaceFill the fill colour and alpha
    vector_float4 glassFace;
    vector_float4 glassFaceFill;
    // Outward refraction in the outer rim (px): x amount, y height, z share at the frame, w fade-out depth
    vector_float4 glassOuter;
    vector_float4 glassTintRed;
    vector_float4 glassTintGreen;
    vector_float4 glassTintBlue;
    vector_float4 bodyCurve[4];
    vector_float4 bodyCurveInfo;
    vector_float4 lens26;
    vector_float4 lens26Face;
    vector_float4 lens26BlurDistance;
    vector_float4 lens26BlurOpacity;
    vector_float4 lens26Blur;
    vector_float4 lens26Aberration;
    vector_float4 lens26AberrationAngle;
    vector_float4 lens26Shadow;
    vector_float4 lens26ShadowOffset;
    vector_float4 lens26Key0;
    vector_float4 lens26Key1;
    vector_float4 lens26Line;
    vector_float4 lens26Red0;
    vector_float4 lens26Green0;
    vector_float4 lens26Blue0;
    vector_float4 lens26Red1;
    vector_float4 lens26Green1;
    vector_float4 lens26Blue1;
    vector_float4 lens26Items;
    vector_float4 flexGlow;
    vector_float4 flexGlowCenter;
    vector_float4 flexBigRed;
    vector_float4 flexBigGreen;
    vector_float4 flexBigBlue;
};
static_assert(sizeof(NGTheseusParams)==1152,"existing Theseus Metal uniform ABI");
