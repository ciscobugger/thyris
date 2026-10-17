import QtQml

// Qt WebEngine's WebEngineSettings for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum ImageAnimationPolicy { Allow = 1, AnimateOnce = 2, Disallow = 3 }
    enum UnknownUrlSchemePolicy { DisallowUnknownUrlSchemes = 1, AllowUnknownUrlSchemesFromUserInteraction = 2,
        AllowAllUnknownUrlSchemes = 3 }

    // a view's settings: kept, and not applied to the page yet (slice 3)
    property bool javascriptEnabled: true
    property bool errorPageEnabled: true
    property bool pdfViewerEnabled: true
    property bool pluginsEnabled: false
    property bool printElementBackgrounds: true
    property bool screenCaptureEnabled: false
    property int unknownUrlSchemePolicy: WebEngineSettings.AllowUnknownUrlSchemesFromUserInteraction
}
