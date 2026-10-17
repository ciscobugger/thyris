#include "backdrop.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QScreen>
#include <QTimer>
#include <algorithm>
#include <memory>

static bool offscreen() { return QGuiApplication::platformName() == u"offscreen"; }

// `text` as a quoted Lua string, for Hyprland's dispatchers
static QString luaString(QString text) {
    return u'"' + text.replace(u'\\', QStringLiteral("\\\\")).replace(u'"', QStringLiteral("\\\"")) + u'"';
}

// the app's first shown window
static QWindow *ourWindow() {
    for (QWindow *w : QGuiApplication::topLevelWindows())
        if (w->isVisible())
            return w;
    return nullptr;
}

// The shown windows Hyprland lists under the app's own class, in the order they were shown, as Hyprland lists them: not
// a sign-in in the notch (shown under an app_id of its own, Windows.showAs) and not a menu or a page's select popup,
// which are no toplevels there.
QList<QWindow *> Backdrop::ours() const {
    QList<QWindow *> out;
    for (QWindow *w : QGuiApplication::topLevelWindows())
        if (w->isVisible() && (w->type() == Qt::Window || w->type() == Qt::Dialog) && w->property("appId").toString().isEmpty())
            out << w;
    std::stable_sort(out.begin(), out.end(), [this](QWindow *a, QWindow *b) { return m_shown.value(a) < m_shown.value(b); });
    return out;
}

Backdrop::Backdrop(QObject *parent) : QObject(parent) {
    if (!offscreen() && QGuiApplication::primaryScreen())
        m_screenSize = QGuiApplication::primaryScreen()->size();
    QCoreApplication::instance()->installEventFilter(this);
}

bool Backdrop::eventFilter(QObject *object, QEvent *event) {
    if (event->type() == QEvent::Show && object->isWindowType())
        m_shown.insert(static_cast<QWindow *>(object), ++m_shows);
    else if (event->type() == QEvent::Hide && object->isWindowType())
        m_shown.remove(static_cast<QWindow *>(object));
    return false;
}

bool Backdrop::ask(const QByteArray &command, std::function<void(const QByteArray &)> done) {
    if (offscreen()) {
        // engine checks: j/clients from fakeClients, and what would go to Hyprland kept in `dispatched`
        const bool active = command == "j/activeworkspace" && m_fakeWorkspace.isValid();
        if (!m_fakeClients.isValid() || (command != "j/clients" && !active && !command.startsWith("dispatch")))
            return false;
        const bool list = command == "j/clients";
        if (!list && !active)
            m_dispatched << QString::fromUtf8(command);
        const QByteArray reply = list ? m_fakeClients.toString().toUtf8()
                                 : active ? QByteArray("{\"id\":") + QByteArray::number(m_fakeWorkspace.toInt()) + "}" : QByteArray("ok");
        QTimer::singleShot(0, this, [done, reply] { done(reply); });
        return true;
    }
    const QByteArray signature = qgetenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (signature.isEmpty())
        return false;
    auto *socket = new QLocalSocket(this);
    auto reply = std::make_shared<QByteArray>();
    auto finished = std::make_shared<bool>(false);
    const auto finish = [socket, reply, finished, done] {
        if (*finished)
            return;
        *finished = true;
        if (socket->isOpen())
            *reply += socket->readAll();
        socket->deleteLater();
        done(*reply);
    };
    // Hyprland reads the request as soon as it accepts, and its main loop waits (5 s, observed) until the
    // request arrives. Queued for our event loop, the request waited behind a frame whose swap waited on
    // Hyprland: the whole screen froze on switching to the browser's workspace. Written and flushed at once.
    const auto send = [socket, command, sent = std::make_shared<bool>(false)] {
        if (*sent)
            return;
        *sent = true;
        socket->write(command);
        socket->flush();
    };
    connect(socket, &QLocalSocket::connected, socket, send);
    connect(socket, &QLocalSocket::readyRead, socket, [socket, reply] { *reply += socket->readAll(); });
    // Hyprland closes the connection once it has answered
    connect(socket, &QLocalSocket::disconnected, this, finish);
    connect(socket, &QLocalSocket::errorOccurred, this, [finish](QLocalSocket::LocalSocketError e) {
        if (e != QLocalSocket::PeerClosedError)
            finish();
    });
    // a request Hyprland never answers (hung, reloading) must not block every later one
    QTimer::singleShot(500, socket, [socket, finish] {
        socket->abort();
        finish();
    });
    socket->connectToServer(qEnvironmentVariable("XDG_RUNTIME_DIR") + u"/hypr/" + QString::fromLocal8Bit(signature)
                              + u"/.socket.sock");
    if (socket->state() == QLocalSocket::ConnectedState)
        send();
    return true;
}

// Hyprland's layout coordinates are global; the screen's origin makes them the screen's
QPoint Backdrop::screenOrigin(QWindow *window) const {
    QScreen *screen = window ? window->screen() : QGuiApplication::primaryScreen();
    return screen ? screen->geometry().topLeft() : QPoint();
}

// Hyprland's windows of this process under the app's own class, matched to ours: by title where a title names one
// window on each side, the rest in the order they were shown (Hyprland lists windows in the order they mapped, and a
// window hidden and shown again, the first window reused by Ctrl+N, maps anew).
QHash<QWindow *, Backdrop::Place> Backdrop::match(const QByteArray &reply) const {
    const qint64 pid = QCoreApplication::applicationPid();
    QList<QJsonObject> clients;
    for (const QJsonValue &v : QJsonDocument::fromJson(reply).array()) {
        const QJsonObject client = v.toObject();
        if (client.value(u"pid").toInteger() == pid && client.value(u"mapped").toBool(true)
            && client.value(u"class").toString() == QGuiApplication::desktopFileName())
            clients << client;
    }
    const QList<QWindow *> windows = ours();
    QHash<QWindow *, Place> out;
    const auto take = [&](QWindow *w, const QJsonObject &client) {
        const QJsonArray at = client.value(u"at").toArray();
        const QJsonObject ws = client.value(u"workspace").toObject();
        const int id = ws.value(u"id").toInt();
        const QString name = ws.value(u"name").toString();
        // as movetoworkspacesilent takes it: a number, special:<name>, or name:<name>
        const QString spec = id > 0 ? QString::number(id) : name.startsWith(u"special") || name.isEmpty() ? name : u"name:" + name;
        out.insert(w, {QPoint(at.at(0).toInt(), at.at(1).toInt()) - screenOrigin(w), spec, client.value(u"address").toString()});
    };
    for (QWindow *w : windows) {
        const auto same = [w](const QJsonObject &c) { return c.value(u"title").toString() == w->title(); };
        const auto named = std::count_if(windows.begin(), windows.end(), [w](QWindow *o) { return o->title() == w->title(); });
        if (named != 1 || std::count_if(clients.begin(), clients.end(), same) != 1)
            continue;
        const auto it = std::find_if(clients.begin(), clients.end(), same);
        take(w, *it);
        clients.erase(it);
    }
    for (QWindow *w : windows)
        if (!out.contains(w) && !clients.isEmpty())
            take(w, clients.takeFirst());
    return out;
}

bool Backdrop::refresh() {
    if (m_asking) {
        m_again = true;
        return true;
    }
    // set first: a failed connect can answer inside ask
    m_asking = true;
    if (!ask("j/clients", [this](const QByteArray &reply) { answered(reply); }))
        m_asking = false;
    return m_asking;
}

void Backdrop::answered(const QByteArray &reply) {
    m_asking = false;
    QWindow *window = ourWindow();
    QScreen *screen = window ? window->screen() : QGuiApplication::primaryScreen();
    const QHash<QWindow *, Place> places = match(reply);
    bool moved = places.size() != m_places.size();
    for (auto it = places.begin(); !moved && it != places.end(); ++it)
        moved = !m_places.contains(it.key()) || m_places.value(it.key()).pos != it->pos;
    m_places = places;
    const QSize size = screen ? screen->size() : m_screenSize;
    const QPoint pos = window && places.contains(window) ? places.value(window).pos : m_windowPos;
    if (moved || size != m_screenSize || pos != m_windowPos) {
        m_screenSize = size;
        m_windowPos = pos;
        emit changed();
    }
    emit refreshed();
    if (m_again) {
        m_again = false;
        refresh();
    }
}

QPoint Backdrop::posOf(QWindow *window) const {
    return window && m_places.contains(window) ? m_places.value(window).pos : m_windowPos;
}

QString Backdrop::workspaceOf(QWindow *window) const {
    return window ? m_places.value(window).workspace : QString();
}

void Backdrop::place(const QVariantList &placements) {
    m_placing.clear();
    for (const QVariant &v : placements) {
        const QVariantMap p = v.toMap();
        m_placing.append({qobject_cast<QWindow *>(p.value(QStringLiteral("window")).value<QObject *>()), p.value(QStringLiteral("workspace")).toString()});
    }
    m_placeTries = 20;
    placeStep();
}

void Backdrop::placeStep() {
    const bool asked = ask("j/clients", [this](const QByteArray &reply) {
        const QHash<QWindow *, Place> places = match(reply);
        m_places = places;
        // not every shown window of ours listed yet: they have not all mapped
        if (places.size() < ours().size() && --m_placeTries > 0) {
            QTimer::singleShot(100, this, &Backdrop::placeStep);
            return;
        }
        for (const Placing &p : std::as_const(m_placing)) {
            QWindow *w = p.window.data();
            const QString workspace = p.workspace;
            if (!w || workspace.isEmpty() || !places.contains(w) || places.value(w).workspace == workspace)
                continue;
            // movetoworkspacesilent as Hyprland's Lua dispatchers take it (0.56): a workspace id as a number, any
            // other selector (name:web, special:scratch) as a string; one request each, as a name may hold a `;`
            bool isId = false;
            workspace.toInt(&isId);
            const QString target = isId ? workspace : luaString(workspace);
            ask("dispatch hl.dsp.window.move({ workspace = " + target.toUtf8() + ", follow = false, window = "
                    + luaString(u"address:" + places.value(w).address).toUtf8() + " })",
                [](const QByteArray &) {});
        }
        m_placing.clear();
    });
    if (!asked)
        m_placing.clear();
}

void Backdrop::focus(QWindow *window) {
    const QPointer<QWindow> w(window);
    ask("j/clients", [this, w](const QByteArray &reply) {
        const QHash<QWindow *, Place> places = match(reply);
        if (w && places.contains(w))
            ask("dispatch hl.dsp.focus({ window = " + luaString(u"address:" + places.value(w).address).toUtf8() + " })", [](const QByteArray &) {});
    });
}

bool Backdrop::bringHere(QWindow *window) {
    const QPointer<QWindow> w(window);
    return ask("j/activeworkspace", [this, w](const QByteArray &active) {
        const QJsonObject at = QJsonDocument::fromJson(active).object();
        const QString here = at.contains(u"id") ? QString::number(at.value(u"id").toInt()) : QString();
        ask("j/clients", [this, w, here](const QByteArray &reply) {
            const QHash<QWindow *, Place> places = match(reply);
            if (!w || !places.contains(w))
                return;
            const Place p = places.value(w);
            const QByteArray address = luaString(u"address:" + p.address).toUtf8();
            if (!here.isEmpty() && p.workspace != here)
                ask("dispatch hl.dsp.window.move({ workspace = " + here.toUtf8() + ", follow = false, window = " + address + " })",
                    [](const QByteArray &) {});
            ask("dispatch hl.dsp.focus({ window = " + address + " })", [](const QByteArray &) {});
        });
    });
}

void Backdrop::askCursor() {
    const bool asked = ask("j/cursorpos", [this](const QByteArray &reply) {
        const QJsonObject at = QJsonDocument::fromJson(reply).object();
        const bool found = at.contains(u"x") && at.contains(u"y");
        emit cursorAnswered(found, found ? QPoint(at.value(u"x").toInt(), at.value(u"y").toInt()) - screenOrigin(ourWindow()) : QPoint());
    });
    if (!asked)
        emit cursorAnswered(offscreen() && m_fakeCursor.isValid(), m_fakeCursor.toPoint());
}
