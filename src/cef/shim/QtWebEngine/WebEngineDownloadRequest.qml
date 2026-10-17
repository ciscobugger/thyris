import QtQml

// Qt WebEngine's WebEngineDownloadRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum DownloadInterruptReason { NoReason = 0, FileFailed = 1, FileAccessDenied = 2, FileNoSpace = 3,
        FileNameTooLong = 5, FileTooLarge = 6, FileVirusInfected = 7, FileTransientError = 10, FileBlocked = 11,
        FileSecurityCheckFailed = 12, FileTooShort = 13, FileHashMismatch = 14, NetworkFailed = 20, NetworkTimeout = 21,
        NetworkDisconnected = 22, NetworkServerDown = 23, NetworkInvalidRequest = 24, ServerFailed = 30,
        ServerBadContent = 33, ServerUnauthorized = 34, ServerCertProblem = 35, ServerForbidden = 36,
        ServerUnreachable = 37, UserCanceled = 40 }
    enum DownloadState { DownloadRequested = 0, DownloadInProgress = 1, DownloadCompleted = 2, DownloadCancelled = 3,
        DownloadInterrupted = 4 }
    enum SavePageFormat { UnknownSaveFormat = -1, SingleHtmlSaveFormat = 0, CompleteHtmlSaveFormat = 1,
        MimeHtmlSaveFormat = 2 }
}
