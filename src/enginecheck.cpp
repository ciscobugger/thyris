#include "enginecheck.h"
#include <QPointingDevice>
#include "engine.h"
#include "passwords.h"
#include "zen.h"
#include "chromeimport.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QLoggingCategory>
#include <QMimeData>
#include <QPdfDocument>
#include <QPdfSelection>
#include <QProcess>
#include <QQuickWindow>
#include <QMutex>
#include <QSet>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslServer>
#include <QTcpServer>
#include <QTcpSocket>
#include <QThread>
#include <QTimer>
#include <QUrlQuery>
#include <QWindow>
#include <cstdio>
#include <cstring>
#include <memory>
#include <qpa/qplatformdrag.h>
#include <qpa/qwindowsysteminterface.h>
#include <atomic>
#include <cerrno>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sqlite3.h>
#include <sys/un.h>
#include <sys/xattr.h>
#include <thread>
#include <unistd.h>

static QWindow *target() {
    QWindow *window = QGuiApplication::focusWindow();
    if (!window && !QGuiApplication::topLevelWindows().isEmpty())
        window = QGuiApplication::topLevelWindows().first();
    return window;
}

void EngineCheck::press(int key, int modifiers, const QString &text) {
    QWindow *window = target();
    // A page's select popup is a window of its own; offscreen nothing gives the focus back when it
    // closes, as a compositor does, and window shortcuts (the R keys) only fire in the focus window.
    if (!QGuiApplication::focusWindow())
        QWindowSystemInterface::handleFocusWindowChanged<QWindowSystemInterface::SynchronousDelivery>(window, Qt::ActiveWindowFocusReason);
    const auto mods = Qt::KeyboardModifiers(modifiers);
    QWindowSystemInterface::handleKeyEvent<QWindowSystemInterface::SynchronousDelivery>(window, QEvent::KeyPress, key, mods, text);
    QWindowSystemInterface::handleKeyEvent<QWindowSystemInterface::SynchronousDelivery>(window, QEvent::KeyRelease, key, mods, text);
}

void EngineCheck::pointer(qreal x, qreal y, int buttons, int modifiers) {
    using Sync = QWindowSystemInterface::SynchronousDelivery;
    QWindow *window = target();
    const QPointF local(x, y);
    const QPointF global = window->mapToGlobal(local);
    if (!m_inside) {
        QWindowSystemInterface::handleEnterEvent<Sync>(window, local, global);
        m_inside = true;
    }
    const int changed = buttons ^ m_buttons;
    const auto button = Qt::MouseButton(changed & -changed); // one button per call
    const QEvent::Type type = !changed ? QEvent::MouseMove : (buttons & changed) ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease;
    QWindowSystemInterface::handleMouseEvent<Sync>(window, local, global, Qt::MouseButtons(buttons), button, type,
                                                   Qt::KeyboardModifiers(modifiers));
    m_buttons = buttons;
}

void EngineCheck::swipe(qreal x, qreal y, int dy, int steps, int stepMs, int dx) {
    static QPointingDevice *pad = [] {
        auto *d = new QPointingDevice(QStringLiteral("check touchpad"), 4242, QInputDevice::DeviceType::TouchPad,
                                      QPointingDevice::PointerType::Finger,
                                      QInputDevice::Capability::Position | QInputDevice::Capability::Scroll | QInputDevice::Capability::PixelScroll,
                                      2, 3);
        QWindowSystemInterface::registerInputDevice(d);
        return d;
    }();
    QWindow *window = target();
    const QPointF local(x, y);
    const QPointF global = window->mapToGlobal(local);
    ulong at = ulong(QDateTime::currentMSecsSinceEpoch() & 0x7fffffff);
    // handleWheelEvent is no template (no Delivery): each event is flushed through at once
    QWindowSystemInterface::handleWheelEvent(window, at, pad, local, global, QPoint(), QPoint(), Qt::NoModifier, Qt::ScrollBegin);
    QWindowSystemInterface::flushWindowSystemEvents();
    const QPoint step(dx / qMax(1, steps), dy / qMax(1, steps));
    for (int i = 0; i < steps; ++i) {
        at += ulong(stepMs);
        QWindowSystemInterface::handleWheelEvent(window, at, pad, local, global, step, step * 3, Qt::NoModifier, Qt::ScrollUpdate);
        QWindowSystemInterface::flushWindowSystemEvents();
    }
    at += ulong(stepMs);
    QWindowSystemInterface::handleWheelEvent(window, at, pad, local, global, QPoint(), QPoint(), Qt::NoModifier, Qt::ScrollEnd);
    QWindowSystemInterface::flushWindowSystemEvents();
}

void EngineCheck::leave() {
    QWindowSystemInterface::handleLeaveEvent<QWindowSystemInterface::SynchronousDelivery>(target());
    m_inside = false;
}

void EngineCheck::drop(qreal x, qreal y, const QString &path) {
    QWindow *window = target();
    QMimeData data;
    data.setUrls({QUrl::fromLocalFile(path)});
    const QPoint at = QPointF(x, y).toPoint();
    const Qt::DropActions actions = Qt::CopyAction | Qt::MoveAction | Qt::LinkAction;
    // enter, a move within, and the drop, as a drag from Files arrives
    QWindowSystemInterface::handleDrag(window, &data, at, actions, Qt::LeftButton, {});
    QWindowSystemInterface::handleDrag(window, &data, at + QPoint(1, 1), actions, Qt::LeftButton, {});
    QWindowSystemInterface::handleDrop(window, &data, at + QPoint(1, 1), actions, Qt::LeftButton, {});
}

void EngineCheck::dragData(QObject *w, qreal x, qreal y, const QString &mime, const QString &text, bool release) {
    auto *window = qobject_cast<QWindow *>(w);
    if (!window)
        return;
    // one object from the drag's first move to the next drag: the window's drop area keeps a pointer to it meanwhile
    if (!m_dragged || m_dragged->data(mime) != text.toUtf8()) {
        m_dragged = std::make_unique<QMimeData>();
        m_dragged->setData(mime, text.toUtf8());
    }
    const QPoint at = QPointF(x, y).toPoint();
    QWindowSystemInterface::handleDrag(window, m_dragged.get(), at, Qt::MoveAction, Qt::LeftButton, {});
    if (release)
        QWindowSystemInterface::handleDrop(window, m_dragged.get(), at, Qt::MoveAction, Qt::LeftButton, {});
}

void EngineCheck::answer(QTcpSocket *socket) {
    connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
        // the whole request so far: its end can lie past 8 KB once a page has stored cookies (the site steps' did, and
        // the server waited on a request that had all come, 2026-10-15)
        const QByteArray head = socket->peek(socket->bytesAvailable());
        // not a request line: a TLS hello from an https attempt. One for silent.test (the name is in the hello's
        // SNI) is taken and never answered, as by a host that drops https.
        if (head.isEmpty() || head.at(0) < 'A' || head.at(0) > 'Z') {
            if (!head.contains("silent.test"))
                socket->abort();
            return;
        }
        if (!head.contains("\r\n\r\n"))
            return;
        socket->readAll();
        const QString path = QString::fromLatin1(head.split(' ').value(1));
        if (path == QLatin1String("/slow"))
            return;
        // closed with no reply: ERR_EMPTY_RESPONSE, in HttpErrorDomain
        if (path == QLatin1String("/empty")) {
            socket->disconnectFromHost();
            return;
        }
        if (path.startsWith(QLatin1String("/file/"))) {
            sendFile(socket, head, path);
            return;
        }
        // "<path>?*" answers that path with any query (an OAuth authorize address, its callback)
        const QString anyQuery = path.section(u'?', 0, 0) + QStringLiteral("?*");
        const QString key = !m_pages.contains(path) && m_pages.contains(anyQuery) ? anyQuery : path;
        const bool found = m_pages.contains(key);
        const QVariant page = m_pages.value(key);
        const QVariantMap entry = page.toMap();
        const QByteArray auth = entry.value(QStringLiteral("auth")).toString().toUtf8();
        const bool signedIn = auth.isEmpty() || head.contains("\r\nAuthorization: Basic " + auth.toBase64() + "\r\n");
        const QByteArray body = signedIn ? (entry.isEmpty() ? page.toString() : entry.value(QStringLiteral("body")).toString()).toUtf8()
                                         : QByteArray("<title>sign in</title>");
        // `status` ("302 Found") in place of 200; `{port}` in `headers` is this server's port (a Location to another .test host)
        const QByteArray ok = entry.contains(QStringLiteral("status")) ? "HTTP/1.1 " + entry.value(QStringLiteral("status")).toString().toUtf8() + "\r\n"
                                                                     : QByteArray("HTTP/1.1 200 OK\r\n");
        QByteArray headers = entry.value(QStringLiteral("headers")).toString().toUtf8();
        headers.replace("{port}", QByteArray::number(socket->localPort()));
        socket->write((!found ? "HTTP/1.1 404 Not Found\r\n" : signedIn ? ok
                       : "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"check\"\r\n")
                      + QByteArray("Content-Type: ") + (entry.contains(QStringLiteral("type")) ? entry.value(QStringLiteral("type")).toString().toUtf8()
                                                                                    : QByteArray("text/html; charset=utf-8"))
                      + (entry.contains(QStringLiteral("headers")) ? "\r\n" + headers : QByteArray())
                      + "\r\nConnection: close\r\nContent-Length: "
                      + QByteArray::number(body.size()) + "\r\n\r\n" + body);
        socket->disconnectFromHost();
    });
}

void EngineCheck::sendFile(QTcpSocket *socket, const QByteArray &head, const QString &path) {
    const QUrl url(QStringLiteral("http://check") + path);
    const QUrlQuery query(url);
    const QByteArray name = url.path().mid(6).toUtf8();
    const qint64 size = qMax(1LL, query.hasQueryItem(QStringLiteral("size")) ? query.queryItemValue(QStringLiteral("size")).toLongLong() : 1000LL);
    const int delay = query.queryItemValue(QStringLiteral("delay")).toInt();
    const qint64 cut = query.hasQueryItem(QStringLiteral("cut")) ? query.queryItemValue(QStringLiteral("cut")).toLongLong() : -1;
    const qsizetype range = head.indexOf("\r\nRange: bytes=");
    const qint64 start = range < 0 ? 0 : head.mid(range + 15).split('-').value(0).toLongLong();
    if (cut >= 0 && start > 0 && !m_resume) {
        socket->write("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        socket->disconnectFromHost();
        return;
    }
    QByteArray reply = start > 0 ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n";
    reply += "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"" + name + "\"\r\n"
             "Accept-Ranges: bytes\r\nETag: \"check\"\r\nLast-Modified: Mon, 01 Sep 2026 00:00:00 GMT\r\nConnection: close\r\n";
    if (start > 0)
        reply += "Content-Range: bytes " + QByteArray::number(start) + "-" + QByteArray::number(size - 1) + "/" + QByteArray::number(size) + "\r\n";
    reply += "Content-Length: " + QByteArray::number(size - start) + "\r\n\r\n";
    socket->write(reply);
    auto *timer = new QTimer(socket);
    auto sent = std::make_shared<qint64>(start);
    connect(timer, &QTimer::timeout, socket, [this, socket, timer, sent, size, cut] {
        if (cut >= 0 && !m_resume && *sent >= cut) {
            timer->stop();
            socket->abort();
            return;
        }
        const qint64 n = qMin<qint64>(1000, size - *sent);
        socket->write(QByteArray(int(n), 'a'));
        *sent += n;
        if (*sent >= size) {
            timer->stop();
            socket->disconnectFromHost();
        }
    });
    timer->start(delay);
}

QVariantMap EngineCheck::attributes(const QString &path) const {
    const QByteArray file = QFile::encodeName(path);
    QVariantMap out;
    QByteArray names(4096, '\0');
    const ssize_t length = ::listxattr(file.constData(), names.data(), size_t(names.size()));
    for (const QByteArray &key : names.left(qMax<ssize_t>(0, length)).split('\0')) {
        if (!key.startsWith("user."))
            continue;
        QByteArray value(4096, '\0');
        const ssize_t n = ::getxattr(file.constData(), key.constData(), value.data(), size_t(value.size()));
        if (n >= 0)
            out.insert(QString::fromUtf8(key), QString::fromUtf8(value.left(n)));
    }
    return out;
}

QVariantMap EngineCheck::filesHolding(const QString &text) const {
    // main.cpp sets it to the throwaway dir in check mode
    const QString root = qEnvironmentVariable("XDG_DATA_HOME");
    if (root.isEmpty())
        return {};
    const QByteArray utf8 = text.toUtf8();
    const QByteArray utf16(reinterpret_cast<const char *>(text.utf16()), text.size() * 2);
    QStringList holding;
    qint64 files = 0, bytes = 0;
    QDirIterator it(root, QDir::Files | QDir::Hidden | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QByteArray all = file.readAll();
        ++files;
        bytes += all.size();
        if (all.contains(utf8) || all.contains(utf16))
            holding << QDir(root).relativeFilePath(path);
    }
    return {{QStringLiteral("files"), files}, {QStringLiteral("bytes"), bytes}, {QStringLiteral("holding"), holding}};
}

int EngineCheck::serve(const QVariantMap &pages) {
    m_pages = pages;
    auto *server = new QTcpServer(this);
    if (!server->listen(QHostAddress::LocalHost))
        return 0;
    connect(server, &QTcpServer::newConnection, this, [this, server] {
        while (QTcpSocket *socket = server->nextPendingConnection())
            answer(socket);
    });
    return server->serverPort();
}

int EngineCheck::serveTls() {
    // only ever under the throwaway XDG_DATA_HOME main.cpp sets in check mode
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()))
        return 0;
    const QString key = data + QStringLiteral("/check-key.pem"), cert = data + QStringLiteral("/check-cert.pem");
    QProcess openssl;
    openssl.start(QStringLiteral("openssl"), {QStringLiteral("req"), QStringLiteral("-x509"), QStringLiteral("-newkey"), QStringLiteral("ec"),
                                              QStringLiteral("-pkeyopt"), QStringLiteral("ec_paramgen_curve:prime256v1"), QStringLiteral("-nodes"),
                                              QStringLiteral("-keyout"), key, QStringLiteral("-out"), cert, QStringLiteral("-days"), QStringLiteral("30"),
                                              QStringLiteral("-subj"), QStringLiteral("/CN=cert.test"), QStringLiteral("-addext"),
                                              QStringLiteral("subjectAltName=DNS:cert.test")});
    if (!openssl.waitForFinished(10000) || openssl.exitCode() != 0)
        return 0;
    QFile keyFile(key), certFile(cert);
    if (!keyFile.open(QIODevice::ReadOnly) || !certFile.open(QIODevice::ReadOnly))
        return 0;
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setLocalCertificate(QSslCertificate(certFile.readAll()));
    config.setPrivateKey(QSslKey(keyFile.readAll(), QSsl::Ec));
    auto *server = new QSslServer(this);
    server->setSslConfiguration(config);
    if (!server->listen(QHostAddress::LocalHost))
        return 0;
    connect(server, &QSslServer::pendingConnectionAvailable, this, [this, server] {
        while (QTcpSocket *socket = server->nextPendingConnection()) {
            answer(socket);
            // the request may have come with the end of the handshake
            if (socket->bytesAvailable() > 0)
                emit socket->readyRead();
        }
    });
    return server->serverPort();
}

int EngineCheck::closedPort() {
    QTcpServer server;
    if (!server.listen(QHostAddress::LocalHost))
        return 0;
    const int port = server.serverPort();
    server.close();
    return port;
}

bool EngineCheck::sendSignal(qint64 pid, int signal) {
    return pid > 0 && ::kill(pid_t(pid), signal) == 0;
}

bool EngineCheck::fakeApp(const QString &scheme, const QString &name) {
    // only ever under the throwaway XDG_DATA_HOME main.cpp sets in check mode
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()))
        return false;
    const QString dir = data + QStringLiteral("/applications");
    QDir().mkpath(dir);
    const QString id = QStringLiteral("browsercheck-") + scheme + QStringLiteral(".desktop");
    QFile desktop(dir + u'/' + id), list(dir + QStringLiteral("/mimeapps.list"));
    if (!desktop.open(QIODevice::WriteOnly) || !list.open(QIODevice::Append))
        return false;
    desktop.write(("[Desktop Entry]\nType=Application\nName=" + name + "\nExec=true %u\nMimeType=x-scheme-handler/" + scheme + ";\n").toUtf8());
    if (list.size() == 0)
        list.write("[Default Applications]\n");
    list.write(("x-scheme-handler/" + scheme + "=" + id + "\n").toUtf8());
    return true;
}

bool EngineCheck::removeCached(const QString &url) {
    const QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
    const QString path = QFileInfo(QUrl(url).toLocalFile()).absoluteFilePath();
    if (cache.isEmpty() || !cache.startsWith(QDir::tempPath()) || !path.startsWith(cache + u'/'))
        return false;
    return QFile::remove(path);
}

QString EngineCheck::fixtureFile(const QString &name, const QString &text) {
    // only ever under the throwaway XDG_DATA_HOME main.cpp sets in check mode
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()) || name.startsWith(u'/') || name.split(u'/').contains(QStringLiteral("..")))
        return {};
    // a relative path makes its folders (the checks' hunspell dictionary, an extension)
    QDir().mkpath(QFileInfo(data + u'/' + name).absolutePath());
    QFile file(data + u'/' + name);
    if (!file.open(QIODevice::WriteOnly) || file.write(text.toUtf8()) < 0)
        return {};
    return file.fileName();
}

QString EngineCheck::fixtureDir(const QString &path) {
    // only ever under the throwaway XDG_DATA_HOME main.cpp sets in check mode
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()) || path.startsWith(u'/') || path.split(u'/').contains(QStringLiteral("..")))
        return {};
    const QString dir = data + u'/' + path;
    return QDir().mkpath(dir) ? dir : QString();
}

namespace {
bool writeFile(const QString &path, const QByteArray &bytes) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}
bool exec(sqlite3 *db, const QString &sql) { return sqlite3_exec(db, sql.toUtf8().constData(), nullptr, nullptr, nullptr) == SQLITE_OK; }
QString quoted(const QString &text) { return u'\'' + QString(text).replace(u'\'', QStringLiteral("''")) + u'\''; }

// A places.sqlite as Firefox's has it, the columns the import reads: the roots, then `bookmarks` and `history`, those
// with `wal` after a checkpoint, so they are in the write-ahead log alone; the connection is left open, in exclusive
// locking mode (no -shm), for the caller to keep. Row ids: roots 1-6 (menu 2, toolbar 3, tags 4, unfiled 5, mobile 6).
sqlite3 *makePlaces(const QString &path, const QVariantList &bookmarks, const QVariantList &history) {
    sqlite3 *db = nullptr;
    if (sqlite3_open(QFile::encodeName(path).constData(), &db) != SQLITE_OK) {
        sqlite3_close(db);
        return nullptr;
    }
    const qint64 now = QDateTime::currentMSecsSinceEpoch() * 1000;
    bool ok = exec(db, QStringLiteral("PRAGMA locking_mode=EXCLUSIVE; PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;"
                                      "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0,"
                                      " hidden INTEGER DEFAULT 0 NOT NULL, last_visit_date INTEGER, guid TEXT);"
                                      "CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL, parent INTEGER,"
                                      " position INTEGER, title LONGVARCHAR, dateAdded INTEGER, guid TEXT);"));
    const char *roots[] = {"root________", "menu________", "toolbar_____", "tags________", "unfiled_____", "mobile______"};
    const char *names[] = {"", "menu", "toolbar", "tags", "unfiled", "mobile"};
    for (int i = 0; i < 6; ++i)
        ok = ok && exec(db, QStringLiteral("INSERT INTO moz_bookmarks VALUES (%1, 2, NULL, %2, %3, '%4', %5, '%6')")
                                .arg(i + 1).arg(i == 0 ? 0 : 1).arg(qMax(0, i - 1)).arg(QLatin1String(names[i])).arg(now).arg(QLatin1String(roots[i])));
    const QMap<QString, int> rootIds{{QStringLiteral("menu"), 2}, {QStringLiteral("toolbar"), 3}, {QStringLiteral("tags"), 4},
                                     {QStringLiteral("unfiled"), 5}, {QStringLiteral("mobile"), 6}};
    const auto scalar = [db](const QString &sql) {
        sqlite3_stmt *row = nullptr;
        qint64 v = -1;
        if (sqlite3_prepare_v2(db, sql.toUtf8().constData(), -1, &row, nullptr) == SQLITE_OK && sqlite3_step(row) == SQLITE_ROW)
            v = sqlite3_column_type(row, 0) == SQLITE_NULL ? -1 : sqlite3_column_int64(row, 0);
        sqlite3_finalize(row);
        return v;
    };
    const auto place = [&](const QString &url) {
        qint64 id = scalar(QStringLiteral("SELECT id FROM moz_places WHERE url = %1").arg(quoted(url)));
        if (id < 0 && exec(db, QStringLiteral("INSERT INTO moz_places (url, title, guid) VALUES (%1, '', 'p%2')").arg(quoted(url)).arg(qHash(url))))
            id = sqlite3_last_insert_rowid(db);
        return id;
    };
    const auto next = [&](qint64 parent) { return scalar(QStringLiteral("SELECT COUNT(*) FROM moz_bookmarks WHERE parent = %1").arg(parent)); };
    for (const bool wal : {false, true}) {
        if (wal)
            ok = ok && exec(db, QStringLiteral("PRAGMA wal_checkpoint(TRUNCATE)"));
        for (const QVariant &v : history) {
            const QVariantMap h = v.toMap();
            if (h.value(QStringLiteral("wal")).toBool() != wal)
                continue;
            const qint64 id = place(h.value(QStringLiteral("url")).toString());
            ok = ok && id >= 0 && exec(db, QStringLiteral("UPDATE moz_places SET title = %1, visit_count = %2, hidden = %3, last_visit_date = %4 WHERE id = %5")
                                               .arg(quoted(h.value(QStringLiteral("title")).toString())).arg(h.value(QStringLiteral("visits")).toInt())
                                               .arg(h.value(QStringLiteral("hidden")).toBool() ? 1 : 0).arg(qint64(h.value(QStringLiteral("last")).toDouble()) * 1000).arg(id));
        }
        for (const QVariant &v : bookmarks) {
            const QVariantMap b = v.toMap();
            if (b.value(QStringLiteral("wal")).toBool() != wal)
                continue;
            const QStringList path = b.value(QStringLiteral("folder")).toString().split(u'/');
            qint64 parent = rootIds.value(path.first(), 3);
            for (const QString &name : path.mid(1)) {
                qint64 folder = scalar(QStringLiteral("SELECT id FROM moz_bookmarks WHERE type = 2 AND parent = %1 AND title = %2").arg(parent).arg(quoted(name)));
                if (folder < 0 && exec(db, QStringLiteral("INSERT INTO moz_bookmarks (type, parent, position, title, dateAdded, guid) VALUES (2, %1, %2, %3, %4, 'f%5')")
                                               .arg(parent).arg(next(parent)).arg(quoted(name)).arg(now).arg(qHash(name))))
                    folder = sqlite3_last_insert_rowid(db);
                parent = folder;
            }
            if (b.value(QStringLiteral("separator")).toBool()) {
                ok = ok && exec(db, QStringLiteral("INSERT INTO moz_bookmarks (type, parent, position, title, dateAdded) VALUES (3, %1, %2, '', %3)")
                                        .arg(parent).arg(next(parent)).arg(now));
                continue;
            }
            const qint64 id = place(b.value(QStringLiteral("url")).toString());
            ok = ok && id >= 0 && parent >= 0
                 && exec(db, QStringLiteral("INSERT INTO moz_bookmarks (type, fk, parent, position, title, dateAdded) VALUES (1, %1, %2, %3, %4, %5)")
                                 .arg(id).arg(parent).arg(next(parent)).arg(quoted(b.value(QStringLiteral("title")).toString())).arg(now));
        }
    }
    if (!ok) {
        sqlite3_close(db);
        return nullptr;
    }
    return db;
}
}

QVariantMap EngineCheck::zenProfile(const QString &name, const QVariantMap &spec) {
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    // `name` may be a path under the data dir (a family member's folder in a made-up home, "fox/.mozilla/firefox"), never up
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()) || name.startsWith(u'/') || name.split(u'/').contains(QStringLiteral("..")))
        return {};
    // `spec.entry`: the desktop entry's name, as the member finds its install by ("firefox": firefox*.desktop); Zen's by default
    const QString entry = spec.value(QStringLiteral("entry"), QString(name).replace(u'/', u'-')).toString();
    const QString root = data + u'/' + name, install = data + u'/' + QString(name).replace(u'/', u'-') + QStringLiteral("-install");
    const QString used = QStringLiteral("bbbb2222.Default (release)"), decoy = QStringLiteral("aaaa1111.Default Profile");
    for (const QString &dir : {root + u'/' + used, root + u'/' + decoy, install, data + QStringLiteral("/applications")})
        if (!QDir().mkpath(dir))
            return {};
    // the install: its program, and the desktop entry that starts it (Zen's finds it by zen*.desktop)
    if (!writeFile(install + QStringLiteral("/zen-bin"), "#!/bin/sh\n")
        || !QFile::setPermissions(install + QStringLiteral("/zen-bin"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner)
        || !writeFile(data + QStringLiteral("/applications/") + entry + QStringLiteral(".desktop"),
                      "[Desktop Entry]\nName=Zen\nType=Application\nExec=" + QFile::encodeName(install) + "/zen-bin %u\n"))
        return {};
    const QByteArray hash = Zen::installHash(install).toLatin1(), other = Zen::installHash(QStringLiteral("/nowhere/old-zen")).toLatin1();
    const QByteArray sections = "Default=" + used.toUtf8() + "\nLocked=1\n\n", decoySection = "Default=" + decoy.toUtf8() + "\nLocked=1\n";
    const QByteArray installs = "[" + hash + "]\n" + sections + "[" + other + "]\n" + decoySection;
    const QByteArray profiles = "[General]\nStartWithLastProfile=1\nVersion=2\n\n[Profile1]\nName=Default Profile\nIsRelative=1\nPath=" + decoy.toUtf8()
        + "\nDefault=1\n\n[Profile0]\nName=" + spec.value(QStringLiteral("name"), QStringLiteral("Default (release)")).toString().toUtf8()
        + "\nIsRelative=1\nPath=" + used.toUtf8() + "\n\n[Install" + hash + "]\n" + sections + "[Install" + other + "]\n" + decoySection;
    if (!writeFile(root + QStringLiteral("/profiles.ini"), profiles) || !writeFile(root + QStringLiteral("/installs.ini"), installs)
        || !writeFile(root + u'/' + used + QStringLiteral("/compatibility.ini"), "[Compatibility]\nLastPlatformDir=" + QFile::encodeName(install) + "\n"))
        return {};
    // the decoy's one bookmark, which the import must not bring
    sqlite3 *decoyDb = makePlaces(root + u'/' + decoy + QStringLiteral("/places.sqlite"),
                                  {QVariantMap{{QStringLiteral("folder"), QStringLiteral("toolbar")}, {QStringLiteral("url"), QStringLiteral("https://decoy.test/")},
                                               {QStringLiteral("title"), QStringLiteral("decoy")}}}, {});
    sqlite3 *db = makePlaces(root + u'/' + used + QStringLiteral("/places.sqlite"), spec.value(QStringLiteral("bookmarks")).toList(),
                             spec.value(QStringLiteral("history")).toList());
    if (!decoyDb || !db)
        return {};
    sqlite3_close(decoyDb);
    m_zenPlaces.append(db);
    // while held, a reader of its own is refused: only a copy can be read
    sqlite3 *reader = nullptr;
    bool locked = false;
    if (sqlite3_open_v2(QFile::encodeName(root + u'/' + used + QStringLiteral("/places.sqlite")).constData(), &reader, SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK)
        locked = sqlite3_exec(reader, "SELECT COUNT(*) FROM moz_places", nullptr, nullptr, nullptr) == SQLITE_BUSY;
    sqlite3_close(reader);
    // key4.db and logins.json, by NSS itself
    if (!spec.value(QStringLiteral("logins")).toList().isEmpty()) {
        QProcess helper;
        helper.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        helper.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--zen-nss"), QStringLiteral("encrypt"), root + u'/' + used});
        helper.write(QJsonDocument(QJsonObject{{QStringLiteral("primary"), spec.value(QStringLiteral("primary")).toString()},
                                               {QStringLiteral("logins"), QJsonArray::fromVariantList(spec.value(QStringLiteral("logins")).toList())}}).toJson());
        helper.closeWriteChannel();
        if (!helper.waitForFinished(30000) || helper.exitStatus() != QProcess::NormalExit || helper.exitCode() != 0)
            return {};
    }
    return {{QStringLiteral("root"), root}, {QStringLiteral("profile"), root + u'/' + used}, {QStringLiteral("decoy"), root + u'/' + decoy},
            {QStringLiteral("locked"), locked}};
}

// mozlz4 as Zen writes its session files, but one literal run: a valid LZ4 block with no match in it
static QByteArray mozLz4(const QByteArray &raw) {
    QByteArray out("mozLz40\0", 8);
    for (int i = 0; i < 4; ++i)
        out.append(char((raw.size() >> (8 * i)) & 0xff));
    qsizetype n = raw.size();
    out.append(char(qMin<qsizetype>(n, 15) << 4));
    if (n >= 15) {
        for (n -= 15; n >= 255; n -= 255)
            out.append(char(255));
        out.append(char(n));
    }
    return out + raw;
}

bool EngineCheck::zenSession(const QString &profile, const QVariantMap &spec) {
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !profile.startsWith(data + u'/'))
        return false;
    sqlite3 *db = nullptr;
    const QString path = profile + QStringLiteral("/cookies.sqlite");
    bool ok = sqlite3_open(QFile::encodeName(path).constData(), &db) == SQLITE_OK
        && exec(db, QStringLiteral("CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, originAttributes TEXT NOT NULL DEFAULT '', name TEXT, value TEXT, host TEXT,"
                                   " path TEXT, expiry INTEGER, lastAccessed INTEGER, creationTime INTEGER, isSecure INTEGER, isHttpOnly INTEGER,"
                                   " inBrowserElement INTEGER DEFAULT 0, sameSite INTEGER DEFAULT 0, schemeMap INTEGER DEFAULT 0,"
                                   " isPartitionedAttributeSet INTEGER DEFAULT 0, updateTime INTEGER)"));
    for (const QVariant &v : spec.value(QStringLiteral("cookies")).toList()) {
        const QVariantMap c = v.toMap();
        // one arg() call: a later one would also fill the %28 of a partition key
        ok = ok && exec(db, QStringLiteral("INSERT INTO moz_cookies (originAttributes, name, value, host, path, expiry, isSecure, isHttpOnly, sameSite)"
                                           " VALUES (%1, %2, %3, %4, %5, %6, %7, %8, %9)")
                                .arg(quoted(c.value(QStringLiteral("attributes")).toString()), quoted(c.value(QStringLiteral("name")).toString()),
                                     quoted(c.value(QStringLiteral("value")).toString()), quoted(c.value(QStringLiteral("host")).toString()),
                                     quoted(c.value(QStringLiteral("path"), QStringLiteral("/")).toString()),
                                     QString::number(c.value(QStringLiteral("expiry")).toLongLong()), QString::number(c.value(QStringLiteral("secure")).toBool() ? 1 : 0),
                                     QString::number(c.value(QStringLiteral("httpOnly")).toBool() ? 1 : 0), QString::number(c.value(QStringLiteral("sameSite")).toInt())));
    }
    sqlite3_close(db);
    if (spec.contains(QStringLiteral("session")))
        ok = ok && writeFile(profile + u'/' + spec.value(QStringLiteral("sessionFile"), QStringLiteral("sessionstore.jsonlz4")).toString(),
                             mozLz4(QJsonDocument(QJsonObject::fromVariantMap(spec.value(QStringLiteral("session")).toMap())).toJson(QJsonDocument::Compact)));
    return ok;
}

QVariantMap EngineCheck::zenCookieCounts(const QString &profile) const {
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()))
        return {};
    // a copy, in the throwaway data dir: opened read-write, which replays its log
    const QString scratch = data + QStringLiteral("/cookie-counts.sqlite");
    for (const char *suffix : {"", "-wal", "-shm"})
        QFile::remove(scratch + QLatin1String(suffix));
    if (!QFile::copy(profile + QStringLiteral("/cookies.sqlite"), scratch))
        return {};
    if (QFileInfo::exists(profile + QStringLiteral("/cookies.sqlite-wal")))
        QFile::copy(profile + QStringLiteral("/cookies.sqlite-wal"), scratch + QStringLiteral("-wal"));
    QList<QPair<QString, bool>> jar;     // host, a domain cookie
    sqlite3 *db = nullptr;
    sqlite3_stmt *row = nullptr;
    if (sqlite3_open_v2(QFile::encodeName(scratch).constData(), &db, SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK
        && sqlite3_prepare_v2(db, "SELECT host, expiry FROM moz_cookies WHERE originAttributes = ''", -1, &row, nullptr) == SQLITE_OK) {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        while (sqlite3_step(row) == SQLITE_ROW) {
            const QString host = QString::fromUtf8(reinterpret_cast<const char *>(sqlite3_column_text(row, 0))).toLower();
            qint64 expiry = sqlite3_column_int64(row, 1);
            if (expiry > 0 && expiry < 100000000000)
                expiry *= 1000;
            if (!host.isEmpty() && (expiry == 0 || expiry > now))
                jar.append({host.startsWith(u'.') ? host.mid(1) : host, host.startsWith(u'.')});
        }
    }
    sqlite3_finalize(row);
    sqlite3_close(db);
    for (const char *suffix : {"", "-wal", "-shm"})
        QFile::remove(scratch + QLatin1String(suffix));
    QVariantMap out;
    for (const auto &c : std::as_const(jar))
        if (!out.contains(c.first)) {
            int n = 0;
            for (const auto &k : std::as_const(jar))
                n += c.first == k.first || (k.second && c.first.endsWith(u'.' + k.first));
            out.insert(c.first, n);
        }
    return out;
}

QVariantMap EngineCheck::zenProbe(const QString &dir) const {
    QProcess helper;
    helper.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--zen-nss"), QStringLiteral("probe"), dir});
    helper.closeWriteChannel();
    if (!helper.waitForFinished(20000))
        return {};
    return QJsonDocument::fromJson(helper.readAllStandardOutput()).object().toVariantMap();
}

QVariantMap EngineCheck::zenDecrypt(const QString &dir) const {
    QProcess helper;
    helper.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--zen-nss"), QStringLiteral("decrypt"), dir});
    helper.write("\n");
    helper.closeWriteChannel();
    if (!helper.waitForFinished(20000))
        return {};
    QByteArray out = helper.readAllStandardOutput();
    const QJsonObject answer = QJsonDocument::fromJson(out).object();
    out.fill(0);
    return {{QStringLiteral("state"), answer.value(QStringLiteral("state")).toString()},
            {QStringLiteral("logins"), answer.value(QStringLiteral("logins")).toArray().size()}};
}

QStringList EngineCheck::entries(const QString &dir) const {
    return QDir(dir).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden);
}

QString EngineCheck::folderStamp(const QString &dir) const {
    QStringList out;
    QDirIterator it(dir, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QFileInfo f = it.nextFileInfo();
        out.append(QDir(dir).relativeFilePath(f.filePath()) + u' ' + QString::number(f.size()) + u' ' + QString::number(f.lastModified().toMSecsSinceEpoch()));
    }
    out.sort();
    return out.join(u'\n');
}

void EngineCheck::launch(const QStringList &args, const QVariantMap &env, bool viaShell, const QString &dir) {
    auto *process = new QProcess(this);
    if (!dir.isEmpty())
        process->setWorkingDirectory(dir);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // a hand-off that fails goes on as a whole browser in normal mode: its home is the throwaway data dir too, so it
    // reads no ~/.zen or other file of the user's (its XDG folders are this process's, main.cpp)
    environment.insert(QStringLiteral("HOME"), qEnvironmentVariable("XDG_DATA_HOME"));
    for (auto it = env.begin(); it != env.end(); ++it)
        environment.insert(it.key(), it.value().toString());
    process->setProcessEnvironment(environment);
    process->setProcessChannelMode(QProcess::MergedChannels);
    const QString self = QCoreApplication::applicationFilePath();
    m_launched = {{QStringLiteral("code"), -1}, {QStringLiteral("ms"), 0}, {QStringLiteral("output"), QString()}};
    auto *clock = new QElapsedTimer;
    clock->start();
    connect(process, &QProcess::finished, this, [this, process, clock](int code, QProcess::ExitStatus status) {
        m_launched = {{QStringLiteral("code"), status == QProcess::NormalExit ? code : -2}, {QStringLiteral("ms"), clock->elapsed()},
                      {QStringLiteral("output"), QString::fromUtf8(process->readAll())}};
        delete clock;
        process->deleteLater();
    });
    // a hand-off that failed would go on as a whole second browser
    QTimer::singleShot(10000, process, [process] { process->kill(); });
    // bash runs the one command of a `-c` in its own place; the `exit` after it keeps the shell between
    if (viaShell)
        process->start(QStringLiteral("/bin/sh"), QStringList{QStringLiteral("-c"), QStringLiteral("\"$0\" \"$@\"; exit $?"), self} + args);
    else
        process->start(self, args);
}

qint64 EngineCheck::pid() const {
    return QCoreApplication::applicationPid();
}

bool EngineCheck::staleSocket(const QString &path) {
    // only ever under the throwaway XDG_RUNTIME_DIR main.cpp sets in check mode
    const QByteArray file = QFile::encodeName(path);
    if (!path.startsWith(qEnvironmentVariable("XDG_RUNTIME_DIR") + u'/') || !path.startsWith(QDir::tempPath())
        || file.size() >= qsizetype(sizeof(sockaddr_un::sun_path)))
        return false;
    QFile::remove(path);
    const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, file.constData(), size_t(file.size()));
    const bool bound = fd >= 0 && ::bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0;
    // closed without listening or unlinking: the file stays, and a connect to it is refused
    if (fd >= 0)
        ::close(fd);
    return bound;
}

void EngineCheck::away() {
    QWindowSystemInterface::handleFocusWindowChanged<QWindowSystemInterface::SynchronousDelivery>(nullptr, Qt::ActiveWindowFocusReason);
}

void EngineCheck::back(QObject *window) {
    QWindow *to = qobject_cast<QWindow *>(window);
    // the main window: the one visible window no other window owns
    for (QWindow *w : QGuiApplication::topLevelWindows())
        if (!to && w->isVisible() && !w->transientParent())
            to = w;
    if (to)
        QWindowSystemInterface::handleFocusWindowChanged<QWindowSystemInterface::SynchronousDelivery>(to, Qt::ActiveWindowFocusReason);
}

void EngineCheck::report(const QString &line) {
    std::printf("%s\n", qPrintable(line));
    std::fflush(stdout);
}

namespace {
// the copy of stdout and stderr (captureOutput), and each pipe's read end and bytes still to pass on
QMutex outputLock;
QByteArray output;
int outputPipes[2] = {-1, -1};
std::atomic<qint64> outputInFlight[2] = {0, 0};
}

void EngineCheck::captureOutput() {
    std::fflush(stdout);
    std::fflush(stderr);
    for (int i = 0; i < 2; ++i) {
        const int stream = i == 0 ? STDOUT_FILENO : STDERR_FILENO;
        int fds[2];
        if (::pipe(fds) != 0)
            return;
        const int real = ::dup(stream);
        if (real < 0 || ::dup2(fds[1], stream) < 0) {
            ::close(fds[0]);
            ::close(fds[1]);
            return;
        }
        ::close(fds[1]);
        outputPipes[i] = fds[0];
        std::thread([in = fds[0], real, i] {
            char buffer[4096];
            for (;;) {
                const ssize_t n = ::read(in, buffer, sizeof buffer);
                if (n < 0 && errno == EINTR)
                    continue;
                if (n <= 0)
                    return;
                outputInFlight[i] += n;
                {
                    QMutexLocker lock(&outputLock);
                    output.append(buffer, n);
                }
                for (ssize_t done = 0; done < n;) {
                    const ssize_t w = ::write(real, buffer + done, size_t(n - done));
                    if (w < 0 && errno == EINTR)
                        continue;
                    if (w <= 0)
                        break;
                    done += w;
                }
                outputInFlight[i] -= n;
            }
        }).detach();
    }
}

bool EngineCheck::outputHolding(const QString &text) const {
    QMutexLocker lock(&outputLock);
    return !text.isEmpty() && (output.contains(text.toUtf8()) || output.contains(text.toLatin1()));
}

int EngineCheck::outputCount(const QString &text) const {
    QMutexLocker lock(&outputLock);
    return text.isEmpty() ? 0 : int(output.count(text.toUtf8()));
}

void EngineCheck::channelLog(bool on, bool quiet) {
    Engine::channelQuiet = quiet;
    // setting the rules runs every category through the filters again
    QLoggingCategory::setFilterRules(on ? QStringLiteral("qt.webengine.webchanneltransport.debug=true") : QString());
}

bool EngineCheck::islandConnect(const QString &path) {
    islandHangUp();
    m_islandHeard.clear();
    m_island = std::make_unique<QLocalSocket>();
    QLocalSocket *socket = m_island.get();
    connect(socket, &QLocalSocket::readyRead, this, [this, socket] {
        while (socket->canReadLine())
            m_islandHeard.append(QJsonDocument::fromJson(socket->readLine()).object().toVariantMap());
    });
    socket->connectToServer(path);
    return socket->waitForConnected(1000);
}

void EngineCheck::islandSay(const QString &line) {
    if (!m_island)
        return;
    m_island->write(line.toUtf8() + '\n');
    m_island->flush();
}

bool EngineCheck::islandConnected() const {
    return m_island && m_island->state() == QLocalSocket::ConnectedState;
}

void EngineCheck::islandHangUp() {
    if (m_island)
        m_island->disconnectFromServer();
}

void EngineCheck::finish(int failures) {
    // the last lines reach the terminal before the quit: each pipe empty and what was read from it passed on (2 s at most)
    std::fflush(stdout);
    std::fflush(stderr);
    for (int waited = 0; waited < 2000; waited += 5) {
        bool empty = true;
        for (int i = 0; i < 2; ++i) {
            int queued = 0;
            if (outputPipes[i] >= 0 && (::ioctl(outputPipes[i], FIONREAD, &queued) != 0 || queued > 0 || outputInFlight[i] > 0))
                empty = false;
        }
        if (empty)
            break;
        QThread::msleep(5);
    }
    QCoreApplication::exit(failures > 0 ? 1 : 0);
}

namespace {
const QString secretsService = QStringLiteral("org.freedesktop.secrets");
const QString secretsPath = QStringLiteral("/org/freedesktop/secrets");
const QString secretsInterface = QStringLiteral("org.freedesktop.Secret.Service");

// dies with the check, should the check itself die first
void dieWithParent() { ::prctl(PR_SET_PDEATHSIG, SIGTERM); }

// the check's own connection to the throwaway bus, apart from the browser's (Passwords.useBus)
QDBusConnection keyringProbe(const QString &address) {
    return QDBusConnection::connectToBus(address, QStringLiteral("check-keyring-probe"));
}
QDBusMessage secretsCall(const QString &path, const QString &interface, const QString &method, const QVariantList &args) {
    QDBusMessage m = QDBusMessage::createMethodCall(secretsService, path, interface, method);
    m.setArguments(args);
    return m;
}
QDBusObjectPath plainSession(QDBusConnection &bus) {
    const QDBusMessage r = bus.call(secretsCall(secretsPath, secretsInterface, QStringLiteral("OpenSession"),
                                                {QStringLiteral("plain"), QVariant::fromValue(QDBusVariant(QString()))}));
    return r.type() == QDBusMessage::ReplyMessage ? qdbus_cast<QDBusObjectPath>(r.arguments().value(1)) : QDBusObjectPath();
}
QString defaultCollection(QDBusConnection &bus) {
    const QDBusMessage r = bus.call(secretsCall(secretsPath, secretsInterface, QStringLiteral("ReadAlias"), {QStringLiteral("default")}));
    return r.type() == QDBusMessage::ReplyMessage ? qdbus_cast<QDBusObjectPath>(r.arguments().value(0)).path() : QString();
}
}

EngineCheck::~EngineCheck() {
    for (sqlite3 *db : std::as_const(m_zenPlaces))
        sqlite3_close(db);
    for (auto *p : {m_keyring.get(), m_keyringBus.get()})
        if (p && p->state() != QProcess::NotRunning) {
            p->terminate();
            if (!p->waitForFinished(2000))
                p->kill();
        }
}

QString EngineCheck::startKeyring(const QString &password) {
    if (!m_keyringAddress.isEmpty())
        return m_keyringAddress;
    // only ever inside the throwaway data dir main.cpp makes in check mode
    const QString root = qEnvironmentVariable("XDG_DATA_HOME");
    if (root.isEmpty() || !root.startsWith(QDir::tempPath()))
        return QString();
    const QString dir = root + QStringLiteral("/kr");
    for (const char *sub : {"/data", "/run", "/home"})
        if (!QDir().mkpath(dir + QLatin1String(sub)))
            return QString();
    QFile::setPermissions(dir + QStringLiteral("/run"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    const QString socket = dir + QStringLiteral("/bus");
    if (QFile::encodeName(socket).size() >= qsizetype(sizeof(sockaddr_un::sun_path)))
        return QString();
    QFile config(dir + QStringLiteral("/bus.conf"));
    if (!config.open(QIODevice::WriteOnly))
        return QString();
    // receive_sender too: dbus-daemon 1.16 refuses a client even the reply to its Hello under a policy of send and own only
    config.write("<!DOCTYPE busconfig PUBLIC \"-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN\" "
                 "\"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd\">\n<busconfig><type>session</type>"
                 "<listen>unix:path=" + QFile::encodeName(socket) + "</listen><auth>EXTERNAL</auth>"
                 "<policy context=\"default\"><allow send_destination=\"*\"/><allow receive_sender=\"*\"/><allow own=\"*\"/></policy></busconfig>\n");
    config.close();
    // nothing of the desktop's: no session bus, display or runtime dir
    QProcessEnvironment env;
    env.insert(QStringLiteral("PATH"), qEnvironmentVariable("PATH", QStringLiteral("/usr/bin:/bin")));
    env.insert(QStringLiteral("HOME"), dir + QStringLiteral("/home"));
    env.insert(QStringLiteral("XDG_DATA_HOME"), dir + QStringLiteral("/data"));
    env.insert(QStringLiteral("XDG_RUNTIME_DIR"), dir + QStringLiteral("/run"));
    m_keyringBus = std::make_unique<QProcess>();
    m_keyringBus->setProcessEnvironment(env);
    m_keyringBus->setChildProcessModifier(dieWithParent);
    m_keyringBus->start(QStringLiteral("dbus-daemon"), {QStringLiteral("--config-file=") + config.fileName(), QStringLiteral("--nofork"), QStringLiteral("--nopidfile")});
    if (!m_keyringBus->waitForStarted(3000))
        return QString();
    const QString address = QStringLiteral("unix:path=") + socket;
    QElapsedTimer clock;
    clock.start();
    while (!QFile::exists(socket) && clock.elapsed() < 3000)
        QThread::msleep(20);
    env.insert(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"), address);
    m_keyring = std::make_unique<QProcess>();
    m_keyring->setProcessEnvironment(env);
    m_keyring->setChildProcessModifier(dieWithParent);
    m_keyring->start(QStringLiteral("gnome-keyring-daemon"), {QStringLiteral("--foreground"), QStringLiteral("--components=secrets"), QStringLiteral("--unlock")});
    if (!m_keyring->waitForStarted(3000))
        return QString();
    // --unlock reads the login keyring's password from stdin, to its end, before it takes the bus name; QProcess writes
    // only from the event loop, which the wait below does not run, so the write is made here
    m_keyring->write(password.toUtf8());
    m_keyring->waitForBytesWritten(3000);
    m_keyring->closeWriteChannel();
    QDBusConnection bus = keyringProbe(address);
    while (clock.elapsed() < 8000 && !(bus.isConnected() && bus.interface()->isServiceRegistered(secretsService))) {
        QThread::msleep(50);
        if (!bus.isConnected()) {
            QDBusConnection::disconnectFromBus(QStringLiteral("check-keyring-probe"));
            bus = keyringProbe(address);
        }
    }
    if (!bus.isConnected() || !bus.interface()->isServiceRegistered(secretsService))
        return QString();
    m_keyringAddress = address;
    m_keyringPassword = password;
    return address;
}

bool EngineCheck::lockKeyring(bool lock) {
    if (m_keyringAddress.isEmpty())
        return false;
    QDBusConnection bus = keyringProbe(m_keyringAddress);
    const QString collection = defaultCollection(bus);
    if (collection.isEmpty() || collection == u"/")
        return false;
    if (lock) {
        const QDBusMessage r = bus.call(secretsCall(secretsPath, secretsInterface, QStringLiteral("Lock"),
                                                    {QVariant::fromValue(QList<QDBusObjectPath>{QDBusObjectPath(collection)})}));
        return r.type() == QDBusMessage::ReplyMessage;
    }
    // gnome-keyring's own way in without its prompt, as the login's PAM module has it
    qDBusRegisterMetaType<SecretValue>();
    const SecretValue master{plainSession(bus), QByteArray(), m_keyringPassword.toUtf8(), QStringLiteral("text/plain")};
    const QDBusMessage r = bus.call(secretsCall(secretsPath, QStringLiteral("org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"),
                                                QStringLiteral("UnlockWithMasterPassword"), {QVariant::fromValue(QDBusObjectPath(collection)), QVariant::fromValue(master)}));
    return r.type() == QDBusMessage::ReplyMessage;
}

QString EngineCheck::chromeHome(const QVariantMap &spec) {
    const QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty() || !data.startsWith(QDir::tempPath()))
        return {};
    const QString home = data + QStringLiteral("/chrome-home"), root = home + u'/' + spec.value(QStringLiteral("dir")).toString();
    const QByteArray secret = spec.value(QStringLiteral("secret")).toString().toUtf8();
    QJsonObject cache;
    for (const QVariant &pv : spec.value(QStringLiteral("profiles")).toList()) {
        const QVariantMap p = pv.toMap();
        const QString dir = root + u'/' + p.value(QStringLiteral("dir")).toString();
        QDir().mkpath(dir);
        cache.insert(p.value(QStringLiteral("dir")).toString(), QJsonObject{{QStringLiteral("name"), p.value(QStringLiteral("name")).toString()},
                     {QStringLiteral("user_name"), p.value(QStringLiteral("email")).toString()}, {QStringLiteral("active_time"), p.value(QStringLiteral("active")).toDouble()}});
        for (const auto &[file, key] : {std::pair{QStringLiteral("Login Data"), QStringLiteral("logins")}, std::pair{QStringLiteral("Login Data For Account"), QStringLiteral("accountLogins")}}) {
            QFile::remove(dir + u'/' + file);
            sqlite3 *db = nullptr;
            if (sqlite3_open(QFile::encodeName(dir + u'/' + file).constData(), &db) != SQLITE_OK)
                return {};
            exec(db, QStringLiteral("CREATE TABLE logins (origin_url VARCHAR NOT NULL, username_value VARCHAR, password_value BLOB, signon_realm VARCHAR NOT NULL DEFAULT '', "
                                    "blacklisted_by_user INTEGER NOT NULL DEFAULT 0)"));
            sqlite3_stmt *st = nullptr;
            sqlite3_prepare_v2(db, "INSERT INTO logins (origin_url, username_value, password_value, blacklisted_by_user) VALUES (?, ?, ?, ?)", -1, &st, nullptr);
            for (const QVariant &lv : p.value(key).toList()) {
                const QVariantMap l = lv.toMap();
                const QByteArray origin = l.value(QStringLiteral("origin")).toString().toUtf8(), user = l.value(QStringLiteral("user")).toString().toUtf8();
                const QByteArray sealed = l.value(QStringLiteral("never")).toBool() ? QByteArray()
                    : ChromeImport::encrypt(l.value(QStringLiteral("password")).toString().toUtf8(), secret, l.value(QStringLiteral("tag")).toString() == u"v10" ? "v10" : "v11");
                sqlite3_bind_text(st, 1, origin.constData(), int(origin.size()), SQLITE_TRANSIENT);
                sqlite3_bind_text(st, 2, user.constData(), int(user.size()), SQLITE_TRANSIENT);
                sqlite3_bind_blob(st, 3, sealed.constData(), int(sealed.size()), SQLITE_TRANSIENT);
                sqlite3_bind_int(st, 4, l.value(QStringLiteral("never")).toBool() ? 1 : 0);
                sqlite3_step(st);
                sqlite3_reset(st);
            }
            sqlite3_finalize(st);
            sqlite3_close(db);
        }
        {
            QFile::remove(dir + QStringLiteral("/Cookies"));
            sqlite3 *cdb = nullptr;
            if (sqlite3_open(QFile::encodeName(dir + QStringLiteral("/Cookies")).constData(), &cdb) != SQLITE_OK)
                return {};
            exec(cdb, QStringLiteral("CREATE TABLE meta (key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)"));
            exec(cdb, QStringLiteral("INSERT INTO meta VALUES ('version', '24')"));
            exec(cdb, QStringLiteral("CREATE TABLE cookies (creation_utc INTEGER NOT NULL DEFAULT 0, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL DEFAULT '', "
                                     "name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, "
                                     "is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, samesite INTEGER NOT NULL DEFAULT -1, is_persistent INTEGER NOT NULL DEFAULT 1)"));
            sqlite3_stmt *st = nullptr;
            sqlite3_prepare_v2(cdb, "INSERT INTO cookies (host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, is_persistent) "
                                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", -1, &st, nullptr);
            for (const QVariant &cv : p.value(QStringLiteral("cookies")).toList()) {
                const QVariantMap c = cv.toMap();
                const QByteArray host = c.value(QStringLiteral("host")).toString().toUtf8(), name = c.value(QStringLiteral("name")).toString().toUtf8();
                const QByteArray value = c.value(QStringLiteral("value")).toString().toUtf8(), path = c.value(QStringLiteral("path"), QStringLiteral("/")).toString().toUtf8();
                const QByteArray partition = c.value(QStringLiteral("partition")).toString().toUtf8();
                const bool plain = c.value(QStringLiteral("plain")).toBool();
                const QByteArray sealed = plain ? QByteArray() : ChromeImport::encrypt(QCryptographicHash::hash(host, QCryptographicHash::Sha256) + value, secret, "v11");
                const qint64 expires = c.value(QStringLiteral("expires")).toLongLong();
                const QByteArray clear = plain ? value : QByteArray();
                sqlite3_bind_text(st, 1, host.constData(), int(host.size()), SQLITE_TRANSIENT);
                sqlite3_bind_text(st, 2, partition.constData(), int(partition.size()), SQLITE_TRANSIENT);
                sqlite3_bind_text(st, 3, name.constData(), int(name.size()), SQLITE_TRANSIENT);
                sqlite3_bind_text(st, 4, clear.constData(), int(clear.size()), SQLITE_TRANSIENT);
                sqlite3_bind_blob(st, 5, sealed.constData(), int(sealed.size()), SQLITE_TRANSIENT);
                sqlite3_bind_text(st, 6, path.constData(), int(path.size()), SQLITE_TRANSIENT);
                sqlite3_bind_int64(st, 7, expires > 0 ? (expires + 11644473600000LL) * 1000 : 0);
                sqlite3_bind_int(st, 8, c.value(QStringLiteral("secure")).toBool() ? 1 : 0);
                sqlite3_bind_int(st, 9, c.value(QStringLiteral("httpOnly")).toBool() ? 1 : 0);
                sqlite3_bind_int(st, 10, c.value(QStringLiteral("sameSite"), -1).toInt());
                sqlite3_bind_int(st, 11, expires > 0 ? 1 : 0);
                sqlite3_step(st);
                sqlite3_reset(st);
            }
            sqlite3_finalize(st);
            sqlite3_close(cdb);
        }
        QFile::remove(dir + QStringLiteral("/History"));
        sqlite3 *db = nullptr;
        if (sqlite3_open(QFile::encodeName(dir + QStringLiteral("/History")).constData(), &db) != SQLITE_OK)
            return {};
        exec(db, QStringLiteral("CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, "
                                "last_visit_time INTEGER NOT NULL DEFAULT 0, hidden INTEGER DEFAULT 0)"));
        sqlite3_stmt *st = nullptr;
        sqlite3_prepare_v2(db, "INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES (?, ?, ?, ?, ?)", -1, &st, nullptr);
        for (const QVariant &hv : p.value(QStringLiteral("history")).toList()) {
            const QVariantMap h = hv.toMap();
            const QByteArray url = h.value(QStringLiteral("url")).toString().toUtf8(), title = h.value(QStringLiteral("title")).toString().toUtf8();
            sqlite3_bind_text(st, 1, url.constData(), int(url.size()), SQLITE_TRANSIENT);
            sqlite3_bind_text(st, 2, title.constData(), int(title.size()), SQLITE_TRANSIENT);
            sqlite3_bind_int(st, 3, h.value(QStringLiteral("visits"), 1).toInt());
            sqlite3_bind_int64(st, 4, (h.value(QStringLiteral("last")).toLongLong() + 11644473600000LL) * 1000);
            sqlite3_bind_int(st, 5, h.value(QStringLiteral("hidden")).toBool() ? 1 : 0);
            sqlite3_step(st);
            sqlite3_reset(st);
        }
        sqlite3_finalize(st);
        sqlite3_close(db);
        // Sessions/Session_<time>: the open tabs as Chromium writes them (SNSS, version 1), for ChromeImport's tabsOf; an
        // older session beside it (oldTabs) that the newest one replaces
        const auto session = [&](const QVariantList &spec, const QString &name) {
            if (spec.isEmpty())
                return;
            const auto le32 = [](qint32 v) { QByteArray b(4, '\0'); for (int i = 0; i < 4; i++) b[i] = char(quint32(v) >> (8 * i)); return b; };
            const auto padded = [](QByteArray b) { return b + QByteArray((4 - b.size() % 4) % 4, '\0'); };
            const auto str8 = [&](const QByteArray &t) { return le32(qint32(t.size())) + padded(t); };
            const auto str16 = [&](const QString &t) { return le32(qint32(t.size())) + padded(QByteArray(reinterpret_cast<const char *>(t.utf16()), 2 * t.size())); };
            const auto pickle = [&](const QByteArray &body) { return le32(qint32(body.size())) + body; };
            QByteArray out = QByteArray("SNSS") + le32(1);
            const auto command = [&](quint8 id, const QByteArray &payload) {
                const quint16 n = quint16(payload.size() + 1);
                out += char(n & 0xff);
                out += char(n >> 8);
                out += char(id);
                out += payload;
            };
            QSet<qint32> typed;
            QHash<qint32, qint32> next;
            QHash<QString, QByteArray> tokens;
            qint32 tab = 100;
            for (const QVariant &tv : spec) {
                const QVariantMap t = tv.toMap();
                const qint32 w = t.value(QStringLiteral("window"), 1).toInt(), id = tab++;
                if (!typed.contains(w)) {
                    typed.insert(w);
                    command(9, le32(w) + le32(t.value(QStringLiteral("popup")).toBool() ? 1 : 0));      // its type: normal, or popup
                }
                command(0, le32(w) + le32(id));
                command(2, le32(id) + le32(t.contains(QStringLiteral("index")) ? t.value(QStringLiteral("index")).toInt() : next[w]++));
                QStringList pages = t.value(QStringLiteral("back")).toStringList();
                pages.append(t.value(QStringLiteral("url")).toString());
                for (int k = 0; k < pages.size(); k++)
                    command(6, pickle(le32(id) + le32(k) + str8(pages[k].toUtf8())
                                      + str16(k == pages.size() - 1 ? t.value(QStringLiteral("title")).toString() : pages[k])));
                command(7, le32(id) + le32(qint32(pages.size() - 1)));
                const QString group = t.value(QStringLiteral("group")).toString();
                if (!group.isEmpty()) {
                    if (!tokens.contains(group)) {
                        QByteArray token(16, '\0');
                        token[0] = char(tokens.size() + 1);
                        tokens.insert(group, token);
                        command(27, pickle(token + str16(group) + le32(0)));
                    }
                    command(25, le32(id) + QByteArray(4, '\0') + tokens.value(group) + QByteArray(1, '\1') + QByteArray(7, '\0'));
                }
                if (t.value(QStringLiteral("closed")).toBool())
                    command(16, le32(id) + QByteArray(12, '\0'));
            }
            QDir().mkpath(dir + QStringLiteral("/Sessions"));
            QFile f(dir + QStringLiteral("/Sessions/") + name);
            if (f.open(QIODevice::WriteOnly))
                f.write(out);
        };
        session(p.value(QStringLiteral("oldTabs")).toList(), QStringLiteral("Session_13360000000000000"));
        session(p.value(QStringLiteral("tabs")).toList(), QStringLiteral("Session_13370000000000000"));
        // Bookmarks: roots bookmark_bar ("bar"), other, synced, folders by name under them
        QJsonObject roots{{QStringLiteral("bookmark_bar"), QJsonObject{{QStringLiteral("type"), QStringLiteral("folder")}, {QStringLiteral("name"), QStringLiteral("Bookmarks bar")}, {QStringLiteral("children"), QJsonArray()}}},
                          {QStringLiteral("other"), QJsonObject{{QStringLiteral("type"), QStringLiteral("folder")}, {QStringLiteral("name"), QStringLiteral("Other bookmarks")}, {QStringLiteral("children"), QJsonArray()}}},
                          {QStringLiteral("synced"), QJsonObject{{QStringLiteral("type"), QStringLiteral("folder")}, {QStringLiteral("name"), QStringLiteral("Mobile bookmarks")}, {QStringLiteral("children"), QJsonArray()}}}};
        const std::function<void(QJsonObject &, QStringList, const QJsonObject &)> place = [&](QJsonObject &folder, QStringList path, const QJsonObject &item) {
            QJsonArray children = folder.value(QStringLiteral("children")).toArray();
            if (path.isEmpty()) {
                children.append(item);
            } else {
                const QString name = path.takeFirst();
                qsizetype at = -1;
                for (qsizetype i = 0; i < children.size(); ++i)
                    if (children.at(i).toObject().value(QStringLiteral("type")).toString() == u"folder" && children.at(i).toObject().value(QStringLiteral("name")).toString() == name)
                        at = i;
                QJsonObject sub = at >= 0 ? children.at(at).toObject()
                                          : QJsonObject{{QStringLiteral("type"), QStringLiteral("folder")}, {QStringLiteral("name"), name}, {QStringLiteral("children"), QJsonArray()}};
                place(sub, path, item);
                if (at >= 0)
                    children.replace(at, sub);
                else
                    children.append(sub);
            }
            folder.insert(QStringLiteral("children"), children);
        };
        for (const QVariant &bv : p.value(QStringLiteral("bookmarks")).toList()) {
            const QVariantMap b = bv.toMap();
            QStringList path = b.value(QStringLiteral("folder"), QStringLiteral("bar")).toString().split(u'/');
            const QString root = path.takeFirst() == u"other" ? QStringLiteral("other") : QStringLiteral("bookmark_bar");
            QJsonObject top = roots.value(root).toObject();
            place(top, path, QJsonObject{{QStringLiteral("type"), QStringLiteral("url")}, {QStringLiteral("url"), b.value(QStringLiteral("url")).toString()},
                                         {QStringLiteral("name"), b.value(QStringLiteral("title")).toString()}, {QStringLiteral("date_added"), QStringLiteral("13370000000000000")}});
            roots.insert(root, top);
        }
        QFile bookmarks(dir + QStringLiteral("/Bookmarks"));
        if (!bookmarks.open(QIODevice::WriteOnly) || bookmarks.write(QJsonDocument(QJsonObject{{QStringLiteral("roots"), roots}, {QStringLiteral("version"), 1}}).toJson()) < 0)
            return {};
    }
    QFile state(root + QStringLiteral("/Local State"));
    if (!state.open(QIODevice::WriteOnly)
        || state.write(QJsonDocument(QJsonObject{{QStringLiteral("profile"), QJsonObject{{QStringLiteral("info_cache"), cache}}}}).toJson()) < 0)
        return {};
    return home;
}

bool EngineCheck::keyringPut(const QVariantMap &attributes, const QString &secret) {
    if (m_keyringAddress.isEmpty())
        return false;
    qDBusRegisterMetaType<SecretValue>();
    qDBusRegisterMetaType<SecretAttributes>();
    QDBusConnection bus = keyringProbe(m_keyringAddress);
    SecretAttributes attrs;
    for (auto it = attributes.cbegin(); it != attributes.cend(); ++it)
        attrs.insert(it.key(), it.value().toString());
    const QVariantMap properties{{QStringLiteral("org.freedesktop.Secret.Item.Label"), QStringLiteral("Safe Storage")},
                                 {QStringLiteral("org.freedesktop.Secret.Item.Attributes"), QVariant::fromValue(attrs)}};
    const SecretValue value{plainSession(bus), QByteArray(), secret.toUtf8(), QStringLiteral("text/plain")};
    const QDBusMessage r = bus.call(secretsCall(defaultCollection(bus), QStringLiteral("org.freedesktop.Secret.Collection"), QStringLiteral("CreateItem"),
                                                {properties, QVariant::fromValue(value), true}));
    return r.type() == QDBusMessage::ReplyMessage;
}

bool EngineCheck::keyringHolds(const QString &origin, const QString &user, const QString &secret) const {
    if (m_keyringAddress.isEmpty())
        return false;
    qDBusRegisterMetaType<SecretValue>();
    qDBusRegisterMetaType<SecretAttributes>();
    QDBusConnection bus = keyringProbe(m_keyringAddress);
    const SecretAttributes attributes{{QStringLiteral("xdg:schema"), QStringLiteral("browser.Password")}, {QStringLiteral("origin"), origin}, {QStringLiteral("user"), user}};
    const QDBusMessage found = bus.call(secretsCall(secretsPath, secretsInterface, QStringLiteral("SearchItems"), {QVariant::fromValue(attributes)}));
    if (found.type() != QDBusMessage::ReplyMessage)
        return false;
    const auto items = qdbus_cast<QList<QDBusObjectPath>>(found.arguments().value(0)) + qdbus_cast<QList<QDBusObjectPath>>(found.arguments().value(1));
    if (secret.isEmpty() || items.isEmpty())
        return !items.isEmpty();
    const QDBusObjectPath session = plainSession(bus);
    for (const QDBusObjectPath &item : items) {
        const QDBusMessage r = bus.call(secretsCall(item.path(), QStringLiteral("org.freedesktop.Secret.Item"), QStringLiteral("GetSecret"), {QVariant::fromValue(session)}));
        if (r.type() == QDBusMessage::ReplyMessage && qdbus_cast<SecretValue>(r.arguments().value(0)).value == secret.toUtf8())
            return true;
    }
    return false;
}

void EngineCheck::grab(QObject *window, const QString &name) const {
    const QString folder = qEnvironmentVariable("BROWSER_CHECK_GRABS");
    auto *w = qobject_cast<QQuickWindow *>(window);
    if (folder.isEmpty() || !w)
        return;
    QDir().mkpath(folder);
    w->grabWindow().save(QDir(folder).filePath(name + QStringLiteral(".png")));
}

void EngineCheck::keep(const QString &path, const QString &name) const {
    const QString folder = qEnvironmentVariable("BROWSER_CHECK_GRABS");
    if (folder.isEmpty())
        return;
    QDir().mkpath(folder);
    QFile::remove(QDir(folder).filePath(name));
    QFile::copy(path, QDir(folder).filePath(name));
}

QString EngineCheck::tempDir() const { return QDir::tempPath(); }

QString EngineCheck::savedPage(const QString &name) const {
    QFile f(QStringLiteral(":/check/") + name);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

QVariantMap EngineCheck::pdf(const QString &path) const {
    QPdfDocument doc;
    if (doc.load(path) != QPdfDocument::Error::None || doc.pageCount() < 1)
        return {{QStringLiteral("pages"), 0}};
    const QSizeF size = doc.pagePointSize(0);
    const QPdfSelection all = doc.getAllText(0);
    const QRectF box = all.boundingRectangle();
    return {{QStringLiteral("pages"), doc.pageCount()}, {QStringLiteral("width"), size.width()}, {QStringLiteral("height"), size.height()},
            {QStringLiteral("text"), all.text()}, {QStringLiteral("left"), box.left()}, {QStringLiteral("top"), box.top()}};
}

QString EngineCheck::pdfColor(const QString &path, qreal fx, qreal fy) const {
    QPdfDocument doc;
    if (doc.load(path) != QPdfDocument::Error::None || doc.pageCount() < 1)
        return {};
    const QSize size = doc.pagePointSize(0).toSize();
    const QImage image = doc.render(0, size);
    return image.isNull() ? QString() : image.pixelColor(qBound(0, int(fx * size.width()), size.width() - 1),
                                                          qBound(0, int(fy * size.height()), size.height() - 1)).name();
}
