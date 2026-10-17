#pragma once

#include <QObject>
#include <QHash>
#include <QSet>
#include <QStringList>
#include <QVariantMap>
#include <qqmlintegration.h>

class QWebEngineUrlSchemeHandler;

// What the browser's own pages need from the engine that QML cannot reach (PLAN.md 3.15, 3.17): the browser: scheme,
// whose pages (browser://settings, browser://pages) are empty documents Main draws over in QML; the profile's fonts;
// spell check dictionaries converted from hunspell's; and the versions About names.
class Engine : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // { qt, webEngine, chromium, security }
    Q_PROPERTY(QVariantMap versions READ versions CONSTANT)
    // the home folder, for "~/Downloads"
    Q_PROPERTY(QString home READ home CONSTANT)
    // one more each time a favicon is kept (iconKept): bindings on keptIcon() read it to be asked again
    Q_PROPERTY(int iconRevision READ iconRevision NOTIFY iconKept)
public:
    explicit Engine(QObject *parent = nullptr);

    // main(), before QtWebEngineQuick::initialize(): registers the browser: scheme and points Chromium at the folder
    // the dictionaries are converted into (QTWEBENGINE_DICTIONARIES_PATH, unless set)
    static void prepare();
    // The title of the browser:// page `host` stands for ("Settings", "Pages and memory"), "" for none: the empty
    // document each engine serves for it (Main draws the page over the view)
    static QString ownTitle(const QString &host);
    // --check-engine: hunspell's .dic and .aff come from the check's own folder, not /usr/share/hunspell
    static inline QString hunspellOverride;
    // main(): Qt WebEngine logs each web channel message whole at debug level, and the login watch's carry passwords
    // (Logins.js): its category (qt.webengine.webchanneltransport) says nothing under a warning, whatever the logging
    // rules ask for. `channelQuiet` false lets the rules decide again (--check-engine shows what they would log).
    static void quietChannel();
    static inline bool channelQuiet = true;

    // Serves the browser: scheme on a profile (the main one and each private one).
    Q_INVOKABLE void attach(QObject *profile);
    // The profile's fonts, which every page on it inherits: { standard, serif, sansSerif, fixed } families ("" is the
    // engine's own) and { size, fixedSize, minimum } in px (0 is the engine's own). Pages already open take them at once.
    Q_INVOKABLE void setFonts(QObject *profile, const QVariantMap &fonts);
    // the families and sizes the profile uses now, the engine's own where none is set
    Q_INVOKABLE QVariantMap fonts(QObject *profile) const;
    // the installed font families, only fixed-width ones with `fixed`
    Q_INVOKABLE QStringList families(bool fixed) const;

    // Spell check (PLAN.md 3.15): Chromium reads <language>.bdic from its dictionaries folder. For each language
    // ("en-GB"): "ready" (its .bdic is there), "hunspell" (hunspell's en_GB.dic and .aff are there to convert) or "".
    Q_INVOKABLE QVariantMap dictionaries(const QStringList &languages) const;
    // Converts the hunspell dictionaries of `languages` that have no .bdic yet (qwebengine_convert_dict, one at a
    // time); answers with converted() once all are done.
    Q_INVOKABLE void convert(const QStringList &languages);
    Q_INVOKABLE QString dictionaryFolder() const;

    // Favicons. Qt's favicon provider answers an image://favicon/ address from the view whose icon it is, and with
    // that view unloaded (Discarded) it crashed the browser in WebContentsAdapter::icon() (2026-10-01: after being
    // left a while). So nothing draws that address: keepIcon saves a live view's favicon once into the cache
    // (iconKept follows, with the file), and every favicon drawn is keptIcon's: the saved copy of an image://favicon/
    // address ("" until there is one), any other address as it is.
    // A copy missing is asked for there and then, unless an unloaded view holds the address (iconUnloaded): the
    // provider answers an address no view has from the profile's favicon database.
    Q_INVOKABLE void keepIcon(const QString &address);
    Q_INVOKABLE QString keptIcon(const QString &address);
    // A view holding `address` was unloaded (true) or loaded again or gone (false); counted, as views share icons
    Q_INVOKABLE void iconUnloaded(const QString &address, bool unloaded);

    // Praxis, Tacit's agent app (PLAN.md 3.20, 4): whether its hand-off (claude-hand) is here, and `prompt` handed to it
    // as a new session in the home folder, which it brings forward. False when it could not be started.
    Q_INVOKABLE bool praxisHere() const;
    Q_INVOKABLE bool askPraxis(const QString &prompt);
    int iconRevision() const { return m_iconRevision; }

    QVariantMap versions() const;
    QString home() const;

signals:
    void converted(const QVariantMap &dictionaries);
    void iconKept(const QString &address, const QString &file);

private:
    void convertNext(QStringList left, QStringList asked);
    QWebEngineUrlSchemeHandler *m_handler = nullptr;
    QString iconFile(const QString &address) const;
    QSet<QString> m_keeping;            // favicons asked of the provider, not answered yet
    QSet<QString> m_unanswered;         // asked and answered with no image: not asked again this run
    QHash<QString, int> m_unloaded;     // addresses held by unloaded views, and by how many
    int m_iconRevision = 0;
};
