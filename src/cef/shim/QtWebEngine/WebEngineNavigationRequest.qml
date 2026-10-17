import QtQml

// Qt WebEngine's WebEngineNavigationRequest for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    enum NavigationRequestAction { AcceptRequest = 0, IgnoreRequest = 255 }
    enum NavigationType { LinkClickedNavigation = 0, TypedNavigation = 1, FormSubmittedNavigation = 2,
        BackForwardNavigation = 3, ReloadNavigation = 4, OtherNavigation = 5, RedirectNavigation = 6 }
}
