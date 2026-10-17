import QtQml

// Qt WebEngine's AuthenticationDialogRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum AuthenticationType { AuthenticationTypeHTTP = 0, AuthenticationTypeProxy = 1 }
}
