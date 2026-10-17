import QtQml

// Qt WebEngine's FileDialogRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum FileMode { FileModeOpen = 0, FileModeOpenMultiple = 1, FileModeUploadFolder = 2, FileModeSave = 3 }
}
