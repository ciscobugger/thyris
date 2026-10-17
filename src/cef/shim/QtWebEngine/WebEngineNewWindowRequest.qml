import QtQml

// Qt WebEngine's WebEngineNewWindowRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum DestinationType { InNewWindow = 0, InNewTab = 1, InNewDialog = 2, InNewBackgroundTab = 3 }
}
