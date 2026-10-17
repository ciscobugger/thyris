import QtQml

// Qt WebEngine's JavaScriptDialogRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum DialogType { DialogTypeAlert = 0, DialogTypeConfirm = 1, DialogTypePrompt = 2, DialogTypeBeforeUnload = 3 }
}
