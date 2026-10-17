import QtQml
import Browser.Cef

// Qt WebEngine's WebEngineProfile for Opsis's QML on CEF (see WebEngineView.qml in this folder). The enums are Qt 6.11's, numbers and all.
QtObject {
    id: profile
    enum HttpCacheType { MemoryHttpCache = 0, DiskHttpCache = 1, NoCache = 2 }
    enum PersistentCookiesPolicy { NoPersistentCookies = 0, AllowPersistentCookies = 1, ForcePersistentCookies = 2,
        OnlyPersistentCookies = 3 }
    enum PersistentPermissionsPolicy { AskEveryTime = 0, StoreInMemory = 1, StoreOnDisk = 2 }

    // A profile with no storage name is off the record: PageItem opens its pages in a request context of their own, in
    // memory (pageitem.cpp, contextOf). Languages, spell check and the cache are Chromium's preferences of that context
    // (CefProfiles); the rest is kept and not CEF's yet.
    property string storageName
    property string persistentStoragePath
    readonly property bool offTheRecord: storageName === ""
    property int persistentPermissionsPolicy: WebEngineProfile.StoreOnDisk
    property string downloadPath
    property string httpAcceptLanguage
    property bool spellCheckEnabled: false
    property var spellCheckLanguages: []
    property var extensionManager: null
    readonly property ScriptCollection userScripts: ScriptCollection {}
    signal downloadRequested(var download)
    signal clearHttpCacheCompleted()
    function clearHttpCache() { CefProfiles.clearHttpCache(profile) }

    // Accept-Language and navigator.languages: Chromium's intl.accept_languages, a plain list that Chromium weighs itself
    function plainLanguages(header) {
        return String(header).split(",").map(p => p.split(";")[0].trim()).filter(l => l !== "").join(",");
    }
    property bool engineReady: false
    onHttpAcceptLanguageChanged: if (engineReady) CefProfiles.setPreference(profile, "intl.accept_languages", plainLanguages(httpAcceptLanguage))
    onSpellCheckEnabledChanged: if (engineReady) CefProfiles.setPreference(profile, "browser.enable_spellchecking", spellCheckEnabled)
    onSpellCheckLanguagesChanged: if (engineReady) CefProfiles.setPreference(profile, "spellcheck.dictionaries", spellCheckLanguages)
    Component.onCompleted: {
        // the engine's own languages until something sets them (Main keeps them as the engine's); spell check as set here,
        // off until Settings has dictionaries for it (Chromium would fetch one it lacks)
        if (httpAcceptLanguage === "")
            httpAcceptLanguage = CefProfiles.preference(profile, "intl.accept_languages") || "";
        engineReady = true;
        CefProfiles.setPreference(profile, "browser.enable_spellchecking", spellCheckEnabled);
    }
    readonly property Connections cacheCleared: Connections {
        target: CefProfiles
        function onHttpCacheCleared(p) { if (p === profile) profile.clearHttpCacheCompleted() }
    }
}
