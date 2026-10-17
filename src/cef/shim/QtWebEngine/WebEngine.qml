pragma Singleton
import QtQml

// Qt WebEngine's WebEngine singleton for Opsis's QML on CEF (see WebEngineView.qml in this folder).
QtObject {
    // a script for a WebEngineScriptCollection, with the properties Qt's has
    function script() {
        return { name: "", sourceCode: "", sourceUrl: "", injectionPoint: WebEngineScript.Deferred, worldId: WebEngineScript.MainWorld,
                 runsOnSubFrames: false };
    }
}
