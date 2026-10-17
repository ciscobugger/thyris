import QtQml

// Qt WebEngine's WebEnginePermission for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum PermissionType { Unsupported = 0, MediaAudioCapture = 1, MediaVideoCapture = 2, MediaAudioVideoCapture = 3,
        DesktopVideoCapture = 4, DesktopAudioVideoCapture = 5, MouseLock = 6, Notifications = 7, Geolocation = 8,
        ClipboardReadWrite = 9, LocalFontsAccess = 10 }
    enum State { Invalid = 0, Ask = 1, Granted = 2, Denied = 3 }
}
