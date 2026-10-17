import QtQml

// Qt WebEngine's WebEngineWebAuthUxRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
// One security-key request of a page's, as Opsis's CEF build says its steps (book4-edge/cef-pgo/webauthn-patch.py,
// PageItem.webAuthnStep): take() each step; the answers go back through the page (PageItem.webAuthnAnswer). A step that
// leaves `state` as it was (a wrong PIN asked again) still says stateChanged, which BrowserView's passkey ask listens to.
QtObject {
    enum PinEntryError { NoError = 0, InternalUvLocked = 1, WrongPin = 2, TooShort = 3, InvalidCharacters = 4,
        SameAsCurrentPin = 5 }
    enum PinEntryReason { Set = 0, Change = 1, Challenge = 2 }
    enum RequestFailureReason { Timeout = 0, KeyNotRegistered = 1, KeyAlreadyRegistered = 2, SoftPinBlock = 3,
        HardPinBlock = 4, AuthenticatorRemovedDuringPinEntry = 5, AuthenticatorMissingResidentKeys = 6,
        AuthenticatorMissingUserVerification = 7, AuthenticatorMissingLargeBlob = 8, NoCommonAlgorithms = 9,
        StorageFull = 10, UserConsentDenied = 11, WinUserCancelled = 12 }
    enum WebAuthUxState { NotStarted = 0, SelectAccount = 1, CollectPin = 2, FinishTokenCollection = 3, RequestFailed = 4,
        Cancelled = 5, Completed = 6 }

    property var page: null             // the PageItem it answers through
    property int request: 0             // the engine's number for it
    property int state: 0               // WebAuthUxState
    property string relyingPartyId: ""
    property var userNames: []
    property int requestFailureReason: -1
    property var pinRequest: ({ reason: 2, error: 0, minPinLength: 4, remainingAttempts: 0 })

    readonly property var failures: ["Timeout", "KeyNotRegistered", "KeyAlreadyRegistered", "SoftPinBlock", "HardPinBlock",
        "AuthenticatorRemovedDuringPinEntry", "AuthenticatorMissingResidentKeys", "AuthenticatorMissingUserVerification",
        "AuthenticatorMissingLargeBlob", "NoCommonAlgorithms", "StorageFull", "UserConsentDenied"]
    readonly property var pinErrors: ["", "InternalUvLocked", "WrongPin", "TooShort", "InvalidCharacters", "SameAsCurrentPin"]

    function take(step) {
        if (step.rp)
            relyingPartyId = step.rp;
        if (step.state === "pin")
            pinRequest = { reason: ["Set", "Change", "Challenge"].indexOf(step.reason) < 0 ? 2 : ["Set", "Change", "Challenge"].indexOf(step.reason),
                           error: Math.max(0, pinErrors.indexOf(step.error ?? "")), minPinLength: step.minLength ?? 4,
                           remainingAttempts: step.attempts ?? 0 };
        if (step.state === "accounts")
            userNames = step.names ?? [];
        if (step.state === "failed")
            requestFailureReason = failures.indexOf(step.failure ?? "");
        const next = ({ touch: 3, pin: 2, accounts: 1, failed: 4, done: 6 })[step.state] ?? (state === 6 ? 6 : 5);
        if (next === state)
            stateChanged();
        else
            state = next;
    }
    function setPin(pin) { page.webAuthnAnswer(request, "pin", pin) }
    function setSelectedAccount(name) { page.webAuthnAnswer(request, "account", String(Math.max(0, userNames.indexOf(name)))) }
    function retry() { page.webAuthnAnswer(request, "retry") }
    function cancel() { page.webAuthnAnswer(request, "cancel") }
}
