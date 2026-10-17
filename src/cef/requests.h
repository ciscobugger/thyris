#pragma once

#include <QAbstractListModel>
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QRect>
#include <QStringList>
#include <QUrl>
#include <functional>
#include <utility>
#include <memory>

class PageItem;

// What becomes of a request: loaded as asked, refused, refused with `body` (of type `mime`) given to the page in its place
// (the filter list's stand-in), or `url` loaded instead (the address without the parameters a list strips)
struct RequestDecision {
    enum Action { Allow, Block, Serve, Load } action = Allow;
    QByteArray mime, body;
    QUrl url;
};

// A profile's request filter (Opsis's ad blocker, src/adblock.cpp), asked on CEF's IO thread for every request a page makes,
// as Qt WebEngine's profile asks its URL request interceptor. `page`: the top document's address (the request's own for a
// main-frame load); `kind`: the request's type as uBlock Origin's lists name it (main_frame, script, image, ...). Called
// with its handle's lock held.
class RequestFilter {
public:
    virtual ~RequestFilter() = default;
    virtual RequestDecision decide(const QUrl &request, const QUrl &page, const char *kind) = 0;
};

// What a page holds of its profile's filter (the profile's "requestFilter" property), on any thread: its filter is null
// once the filter has gone. The filter takes `lock` for its own reads and writes of what refuse() touches, and to go.
struct RequestFilterHandle {
    QMutex lock;
    RequestFilter *filter = nullptr;
    RequestDecision decide(const QUrl &request, const QUrl &page, const char *kind) {
        QMutexLocker locked(&lock);
        return filter ? filter->decide(request, page, kind) : RequestDecision();
    }
};
using RequestFilterRef = std::shared_ptr<RequestFilterHandle>;
Q_DECLARE_METATYPE(RequestFilterRef)

// The requests a page hands Opsis's QML, with the properties and functions of Qt WebEngine's (src/cef/shim):
// each is answered on the GUI thread, and PageClient acts on the answer once the handler returns.

// a navigation about to start: reject() stops it (Qt's WebEngineNavigationRequest)
class NavigationRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(bool isMainFrame MEMBER isMainFrame CONSTANT)
    Q_PROPERTY(int navigationType MEMBER navigationType CONSTANT)
    Q_PROPERTY(bool hasFormData MEMBER hasFormData CONSTANT)
public:
    using QObject::QObject;
    QUrl url;
    bool isMainFrame = true;
    int navigationType = 5;     // Qt's NavigationType: 0 link, 1 typed, 2 form, 3 back/forward, 4 reload, 5 other, 6 redirect
    bool hasFormData = false;
    bool rejected = false;
    Q_INVOKABLE void reject() { rejected = true; }
    Q_INVOKABLE void accept() { rejected = false; }
};

// a page asks for a new page or window (window.open, target=_blank, a modified click): openIn(view) puts it in that view,
// which must be new and not yet loading; not opened, nothing opens (Qt's WebEngineNewWindowRequest)
class NewWindowRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl requestedUrl MEMBER requestedUrl CONSTANT)
    Q_PROPERTY(int destination MEMBER destination CONSTANT)
    Q_PROPERTY(bool userInitiated MEMBER userInitiated CONSTANT)
    Q_PROPERTY(QRect requestedGeometry MEMBER requestedGeometry CONSTANT)
public:
    using QObject::QObject;
    QUrl requestedUrl;
    int destination = 1;        // Qt's DestinationType: 0 window, 1 tab, 2 dialog (a pop-up), 3 background tab
    bool userInitiated = false;
    QRect requestedGeometry;
    PageItem *target = nullptr;
    Q_INVOKABLE void openIn(QObject *view);
};

// The page's back/forward list as Qt WebEngine's history.items gives it (WebEngineHistoryModel): url (role 256),
// title (257), offset from the current entry (258), icon (259). Replaced whole after each main-frame load.
class PageHistoryModel : public QAbstractListModel {
    Q_OBJECT
public:
    struct Entry { QUrl url; QString title; int offset = 0; };
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override { return parent.isValid() ? 0 : int(m_entries.size()); }
    QVariant data(const QModelIndex &at, int role) const override {
        if (!at.isValid() || at.row() >= m_entries.size())
            return {};
        const Entry &e = m_entries.at(at.row());
        switch (role) {
        case Qt::UserRole: return e.url;
        case Qt::UserRole + 1: return e.title;
        case Qt::UserRole + 2: return e.offset;
        case Qt::UserRole + 3: return QUrl();
        default: return {};
        }
    }
    QHash<int, QByteArray> roleNames() const override {
        return {{Qt::UserRole, "url"}, {Qt::UserRole + 1, "title"}, {Qt::UserRole + 2, "offset"}, {Qt::UserRole + 3, "icon"}};
    }
    void setEntries(QList<Entry> entries) {
        beginResetModel();
        m_entries = std::move(entries);
        endResetModel();
    }
private:
    QList<Entry> m_entries;
};

// history: { items }, as Qt WebEngine's WebEngineHistory has it
class PageHistory : public QObject {
    Q_OBJECT
    Q_PROPERTY(PageHistoryModel *items READ items CONSTANT)
public:
    explicit PageHistory(QObject *parent) : QObject(parent), m_items(new PageHistoryModel(this)) {}
    PageHistoryModel *items() const { return m_items; }
private:
    PageHistoryModel *m_items;
};

// the page went into full screen or out of it (Qt's FullScreenRequest): the handler accepts or rejects it while the
// signal runs; a refused entry is undone at once
// a page asks for a permission (Qt's WebEnginePermission): grant() or deny(), once, now or later; one never answered is
// refused when it goes. isValid holds while it can still be answered (the engine drops it when the page moves on).
// Chromium here keeps no answer between loads, so reset() has nothing to forget.
class PermissionRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl origin MEMBER origin CONSTANT)
    Q_PROPERTY(int permissionType MEMBER permissionType CONSTANT)   // Qt's PermissionType numbers
    Q_PROPERTY(bool isValid READ isValid NOTIFY stateChanged)
    Q_PROPERTY(int state READ state NOTIFY stateChanged)            // Qt's State: 0 invalid, 1 ask, 2 granted, 3 denied
public:
    using Answer = std::function<void(bool granted)>;
    PermissionRequest(Answer answer, QObject *parent) : QObject(parent), m_answer(std::move(answer)) {}
    ~PermissionRequest() override {
        if (Answer answer = std::exchange(m_answer, nullptr))
            answer(false);
    }
    QUrl origin;
    int permissionType = 0;
    bool isValid() const { return !m_gone; }
    int state() const { return m_gone && m_state == 1 ? 0 : m_state; }
    Q_INVOKABLE void grant() { finish(true); }
    Q_INVOKABLE void deny() { finish(false); }
    Q_INVOKABLE void reset() {}
    // the engine dropped it (a navigation, the page closing): no answer is taken any more
    void drop() {
        m_answer = nullptr;
        m_gone = true;
        emit stateChanged();
    }
signals:
    void stateChanged();
private:
    void finish(bool granted) {
        if (Answer answer = std::exchange(m_answer, nullptr)) {
            answer(granted);
            m_state = granted ? 2 : 3;
            emit stateChanged();
        }
    }
    Answer m_answer;
    int m_state = 1;
    bool m_gone = false;
};

// a site or a proxy asks for a user name and password (Qt's AuthenticationDialogRequest): dialogAccept(user, password)
// or dialogReject(), answered once, now or later; one the handler leaves (accepted stays false), or never answers, is refused
class AuthRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(QString realm MEMBER realm CONSTANT)
    Q_PROPERTY(QString proxyHost MEMBER proxyHost CONSTANT)
    Q_PROPERTY(int type MEMBER type CONSTANT)       // Qt's AuthenticationType: 0 the site, 1 a proxy
    Q_PROPERTY(bool accepted MEMBER accepted)
public:
    using Answer = std::function<void(bool given, const QString &user, const QString &password)>;
    AuthRequest(Answer answer, QObject *parent) : QObject(parent), m_answer(std::move(answer)) {}
    ~AuthRequest() override { finish(false, {}, {}); }
    QUrl url;
    QString realm;
    QString proxyHost;
    int type = 0;
    bool accepted = false;
    Q_INVOKABLE void dialogAccept(const QString &user, const QString &password) { finish(true, user, password); }
    Q_INVOKABLE void dialogReject() { finish(false, {}, {}); }
private:
    void finish(bool given, const QString &user, const QString &password) {
        if (Answer answer = std::exchange(m_answer, nullptr))
            answer(given, user, password);
    }
    Answer m_answer;
};

class FullScreenRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool toggleOn MEMBER toggleOn CONSTANT)
    Q_PROPERTY(QUrl origin MEMBER origin CONSTANT)
public:
    using QObject::QObject;
    bool toggleOn = false;
    QUrl origin;
    bool accepted = false;
    Q_INVOKABLE void accept() { accepted = true; }
    Q_INVOKABLE void reject() { accepted = false; }
};

// a page's file input asks for files (Qt's FileDialogRequest): dialogAccept(paths) or dialogReject(), answered once;
// one never answered is nothing chosen when it goes, and so is one the handler leaves (accepted stays false)
class FileRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(int mode MEMBER mode CONSTANT)   // Qt's FileMode: 0 one file, 1 several, 2 a folder, 3 save
    Q_PROPERTY(QString defaultFileName MEMBER defaultFileName CONSTANT)
    Q_PROPERTY(QStringList acceptedMimeTypes MEMBER acceptedMimeTypes CONSTANT)
    Q_PROPERTY(bool accepted MEMBER accepted)
    // Chromium keeps an input's files when its pick is cancelled; Qt WebEngine's request (without this) cleared them
    Q_PROPERTY(bool rejectKeepsFiles READ rejectKeepsFiles CONSTANT)
public:
    using Answer = std::function<void(const QStringList &paths)>;
    bool rejectKeepsFiles() const { return true; }
    FileRequest(Answer answer, QObject *parent) : QObject(parent), m_answer(std::move(answer)) {}
    ~FileRequest() override { finish({}); }
    int mode = 0;
    QString defaultFileName;
    QStringList acceptedMimeTypes;
    bool accepted = false;
    Q_INVOKABLE void dialogAccept(const QStringList &paths) { finish(paths); deleteLater(); }
    Q_INVOKABLE void dialogReject() { finish({}); deleteLater(); }
private:
    void finish(const QStringList &paths) {
        if (Answer answer = std::exchange(m_answer, nullptr))
            answer(paths);
    }
    Answer m_answer;
};

// a certificate the engine questions for a load (Qt's WebEngineCertificateError): the load waits while the handler
// holds it (defer()) until acceptCertificate() or rejectCertificate(); one neither deferred nor answered in the handler,
// or never answered, is refused. certificateDer: the leaf certificate (Facts.certificate reads it).
class CertificateError : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(bool isMainFrame MEMBER isMainFrame CONSTANT)
    Q_PROPERTY(int type MEMBER type CONSTANT)   // Chromium's net error, Qt's Type numbers (-202 an unknown authority, ...)
    Q_PROPERTY(bool overridable MEMBER overridable CONSTANT)
    Q_PROPERTY(QByteArray certificateDer MEMBER certificateDer CONSTANT)
public:
    using Answer = std::function<void(bool accept)>;
    CertificateError(Answer answer, QObject *parent) : QObject(parent), m_answer(std::move(answer)) {}
    ~CertificateError() override { finish(false); }
    QUrl url;
    bool isMainFrame = true;
    int type = 0;
    bool overridable = false;
    QByteArray certificateDer;
    bool deferred = false;
    bool answered() const { return !m_answer; }
    Q_INVOKABLE void defer() { deferred = true; }
    Q_INVOKABLE void acceptCertificate() { finish(true); deleteLater(); }
    Q_INVOKABLE void rejectCertificate() { finish(false); deleteLater(); }
private:
    void finish(bool accept) {
        if (Answer answer = std::exchange(m_answer, nullptr))
            answer(accept);
    }
    Answer m_answer;
};

// a page's alert(), confirm(), prompt() or leave-page question (Qt's JavaScriptDialogRequest): the page waits for
// dialogAccept(text) or dialogReject(), answered once; one never answered is Cancel when it goes. The handler sets
// accepted to show it itself; a request it leaves is Cancel at once.
class DialogRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(int type MEMBER type CONSTANT)   // Qt's DialogType: 0 alert, 1 confirm, 2 prompt, 3 leave the page
    Q_PROPERTY(QString message MEMBER message CONSTANT)
    Q_PROPERTY(QString defaultText MEMBER defaultText CONSTANT)
    Q_PROPERTY(QUrl securityOrigin MEMBER securityOrigin CONSTANT)
    Q_PROPERTY(bool accepted MEMBER accepted)
public:
    using Answer = std::function<void(bool ok, const QString &text)>;
    DialogRequest(Answer answer, QObject *parent) : QObject(parent), m_answer(std::move(answer)) {}
    ~DialogRequest() override { finish(false, QString()); }
    int type = 0;
    QString message, defaultText;
    QUrl securityOrigin;
    bool accepted = false;
    Q_INVOKABLE void dialogAccept(const QString &text = QString()) { finish(true, text); deleteLater(); }
    Q_INVOKABLE void dialogReject() { finish(false, QString()); deleteLater(); }
private:
    void finish(bool ok, const QString &text) {
        if (Answer answer = std::exchange(m_answer, nullptr))
            answer(ok, text);
    }
    Answer m_answer;
};

// A download (Qt's WebEngineDownloadRequest), handed to the profile's downloadRequested with the view that started it.
// The handler sets downloadDirectory and accept()s it, or leaves it, and it does not start. downloadFileName is the
// engine's suggested name, made unique in downloadDirectory (" (1)" before the extension, as Chromium does). While it
// comes it is written as <name>.download beside the file, renamed when it lands (CEF writes the file under its own name,
// so a half file looked whole in Files). GUI thread only; PageClient (src/cef/pageitem.cpp) feeds it the engine's
// updates. state and interruptReason are Qt's numbers (Chromium's, as CEF's are).
class DownloadRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl url MEMBER url CONSTANT)
    Q_PROPERTY(QString suggestedFileName MEMBER suggestedFileName CONSTANT)
    Q_PROPERTY(QString mimeType MEMBER mimeType CONSTANT)
    Q_PROPERTY(QObject *view READ view CONSTANT)
    Q_PROPERTY(QString downloadDirectory READ downloadDirectory WRITE setDownloadDirectory NOTIFY downloadDirectoryChanged)
    Q_PROPERTY(QString downloadFileName READ downloadFileName NOTIFY downloadFileNameChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY totalBytesChanged)
    Q_PROPERTY(qint64 receivedBytes READ receivedBytes NOTIFY receivedBytesChanged)
    Q_PROPERTY(int state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool isPaused READ isPaused NOTIFY isPausedChanged)
    Q_PROPERTY(bool isFinished READ isFinished NOTIFY isFinishedChanged)
    Q_PROPERTY(int interruptReason READ interruptReason NOTIFY interruptReasonChanged)
public:
    enum State { Requested = 0, InProgress = 1, Completed = 2, Cancelled = 3, Interrupted = 4 };
    enum Control { Cancel, Pause, Resume };
    // what the engine says of it, each update
    struct Update {
        qint64 total = -1, received = 0;
        bool inProgress = false, complete = false, canceled = false, interrupted = false, paused = false;
        int reason = 0;
    };
    DownloadRequest(QObject *view, QObject *parent) : QObject(parent), m_view(view) {}
    ~DownloadRequest() override;
    QUrl url;
    QString suggestedFileName;
    QString mimeType;
    QObject *view() const { return m_view; }
    QString downloadDirectory() const { return m_directory; }
    void setDownloadDirectory(const QString &directory);
    QString downloadFileName() const { return m_fileName; }
    qint64 totalBytes() const { return m_total; }
    qint64 receivedBytes() const { return m_received; }
    int state() const { return m_state; }
    bool isPaused() const { return m_paused; }
    bool isFinished() const { return m_state == Completed || m_state == Cancelled; }
    int interruptReason() const { return m_reason; }
    bool accepted() const { return m_accepted; }
    // where it is written while it comes
    QString partPath() const { return m_directory + QLatin1Char('/') + m_fileName + QStringLiteral(".download"); }
    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void pause() { control(Pause); }
    Q_INVOKABLE void resume() { control(Resume); }

    // PageClient's: starts it at a path (once), and the engine's controls (the newest update's)
    std::function<void(const QString &path)> start;
    std::function<void(Control)> engine;
    // the engine let it go (the view it came from closed, or it ended): no more updates
    std::function<void()> released;
    void update(const Update &u);

signals:
    void downloadDirectoryChanged();
    void downloadFileNameChanged();
    void totalBytesChanged();
    void receivedBytesChanged();
    void stateChanged();
    void isPausedChanged();
    void isFinishedChanged();
    void interruptReasonChanged();

private:
    void control(Control c) {
        if (engine)
            engine(c);
    }
    void setState(int state);
    QPointer<QObject> m_view;
    QString m_directory;
    QString m_fileName;
    qint64 m_total = -1, m_received = 0;
    int m_state = Requested;
    bool m_paused = false;
    int m_reason = 0;
    bool m_accepted = false;
};
