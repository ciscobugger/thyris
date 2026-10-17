import QtQuick

// The shell's motion system (tacit-shell modules/common/widgets/Anim.qml, copied from caelestia, GPL-3.0), as
// Files uses it: one typed animation, so a site says `Anim { type: Anim.FastSpatial }` instead of a
// duration and a curve. Tokens in Theme.anim, copied from the shell's Appearance.animationCurves.
NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    readonly property QtObject curves: Theme.anim

    duration: {
        if (type < Anim.StandardSmall || type > Anim.SlowEffects)
            return curves.normalDuration;

        if (type === Anim.FastSpatial)
            return curves.expressiveFastSpatialDuration;
        if (type === Anim.DefaultSpatial)
            return curves.expressiveDefaultSpatialDuration;
        if (type === Anim.SlowSpatial)
            return curves.expressiveSlowSpatialDuration;
        if (type === Anim.FastEffects)
            return curves.expressiveFastEffectsDuration;
        if (type === Anim.DefaultEffects)
            return curves.expressiveDefaultEffectsDuration;
        if (type === Anim.SlowEffects)
            return curves.expressiveSlowEffectsDuration;

        const durations = [curves.smallDuration, curves.normalDuration, curves.largeDuration, curves.extraLargeDuration];
        return durations[type % 4]; // 0-7 are the 4 standard types
    }

    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        if (type === Anim.FastSpatial)
            return curves.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return curves.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return curves.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return curves.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return curves.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return curves.expressiveSlowEffects;

        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return curves.emphasized;
        return curves.standard;
    }
}
