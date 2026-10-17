import QtQml

// Qt WebEngine's WebEngineScript for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum InjectionPoint { Deferred = 0, DocumentReady = 1, DocumentCreation = 2 }
    enum ScriptWorldId { MainWorld = 0, ApplicationWorld = 1, UserWorld = 2 }
}
