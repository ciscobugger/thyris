import QtQml

// Qt WebEngine's WebEngineCertificateError for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum Type { SslObsoleteVersion = -218, CertificateKnownInterceptionBlocked = -217, CertificateSymantecLegacy = -215,
        CertificateTransparencyRequired = -214, CertificateValidityTooLong = -213,
        CertificateNameConstraintViolation = -212, CertificateWeakKey = -211, CertificateNonUniqueName = -210,
        CertificateWeakSignatureAlgorithm = -208, CertificateInvalid = -207, CertificateRevoked = -206,
        CertificateUnableToCheckRevocation = -205, CertificateNoRevocationMechanism = -204,
        CertificateContainsErrors = -203, CertificateAuthorityInvalid = -202, CertificateDateInvalid = -201,
        CertificateCommonNameInvalid = -200, SslPinnedKeyNotInCertificateChain = -150, Ok = 0 }
}
