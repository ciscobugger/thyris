#include "devtoolsbridge.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QWebSocket>

DevToolsBridge::DevToolsBridge(std::function<void(const QByteArray &)> send, QObject *parent)
    : QObject(parent), m_send(std::move(send)) {
    const quint64 a = QRandomGenerator::system()->generate64(), b = QRandomGenerator::system()->generate64();
    m_token = QString::number(a, 16) + QString::number(b, 16);
    if (!m_server.listen(QHostAddress::LocalHost, 0))
        qWarning("DevToolsBridge: no port on 127.0.0.1: %s", qPrintable(m_server.errorString()));
    connect(&m_server, &QWebSocketServer::newConnection, this, &DevToolsBridge::connected);
}

// What the front end left on in the page's one session goes off with it: paused scripts run on, breakpoints and the
// element highlight go, emulation ends, and new frames and workers no longer wait for a debugger that has gone.
DevToolsBridge::~DevToolsBridge() {
    if (m_socket)
        m_socket->abort();
    if (!m_send)
        return;     // a spare that never had a page
    ownCall("Target.setAutoAttach", R"({"autoAttach":false,"waitForDebuggerOnStart":false,"flatten":true})");
    for (const char *method : {"Debugger.disable", "Overlay.disable", "DOM.disable", "CSS.disable", "Network.disable",
                               "Profiler.disable", "HeapProfiler.disable", "Emulation.clearDeviceMetricsOverride"})
        ownCall(method, "{}");
}

void DevToolsBridge::bind(std::function<void(const QByteArray &)> send) {
    m_send = std::move(send);
    for (const QByteArray &message : std::exchange(m_waiting, {}))
        m_send(message);
}

QUrl DevToolsBridge::frontEndUrl() const {
    return QUrl(QStringLiteral("devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:%1/%2&can_dock=true").arg(m_server.serverPort()).arg(m_token));
}

// one front end at a time, from a devtools: page, at this relay's path; a newer one (the front end reloaded) takes over
void DevToolsBridge::connected() {
    while (QWebSocket *socket = m_server.nextPendingConnection()) {
        if (socket->requestUrl().path() != QLatin1Char('/') + m_token || !socket->origin().startsWith(QStringLiteral("devtools://"))) {
            qWarning("DevToolsBridge: refused a connection from %s", qPrintable(socket->origin()));
            socket->abort();
            socket->deleteLater();
            continue;
        }
        if (m_socket)
            m_socket->deleteLater();
        m_socket = socket;
        m_asked.clear();
        m_documentLoaded = false;
        connect(socket, &QWebSocket::textMessageReceived, this, &DevToolsBridge::fromFrontEnd);
        connect(socket, &QWebSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QObject::destroyed, this, &DevToolsBridge::stateChanged);
        emit stateChanged();
    }
}

QVariantMap DevToolsBridge::state() const {
    return {{QStringLiteral("connected"), !m_socket.isNull()}, {QStringLiteral("document"), m_documentLoaded},
            {QStringLiteral("inspected"), m_inspected}};
}

qint64 DevToolsBridge::leadingId(const char *data, qsizetype size) {
    static const char lead[] = "{\"id\":";
    const qsizetype n = sizeof(lead) - 1;
    if (size <= n || qstrncmp(data, lead, n) != 0)
        return -1;
    qint64 id = 0;
    for (qsizetype i = n; i < size && data[i] >= '0' && data[i] <= '9'; ++i)
        id = id * 10 + (data[i] - '0');
    return id;
}

// the id moved past frontEnd in place (the front end writes it first), the call remembered by method
void DevToolsBridge::fromFrontEnd(const QString &text) {
    const QByteArray message = text.toUtf8();
    const qint64 id = leadingId(message.constData(), message.size());
    if (id < 0)
        return;
    const qsizetype at = message.indexOf("\"method\":\""), from = at + 10;
    m_asked.insert(id, at < 0 ? QByteArray() : message.mid(from, message.indexOf('"', from) - from));
    const QByteArray moved = "{\"id\":" + QByteArray::number(id + frontEnd) + message.mid(6 + QByteArray::number(id).size());
    if (m_send)
        m_send(moved);
    else
        m_waiting << moved;
}

void DevToolsBridge::fromPage(const QByteArray &message, qint64 id) {
    if (id >= own) {
        // DOM.getNodeForLocation's answer: the front end reveals the node as if its own inspect tool had picked it
        const QJsonObject result = QJsonDocument::fromJson(message).object().value(QStringLiteral("result")).toObject();
        const int node = result.value(QStringLiteral("backendNodeId")).toInt();
        if (node > 0 && m_socket) {
            m_socket->sendTextMessage(QStringLiteral(R"({"method":"Overlay.inspectNodeRequested","params":{"backendNodeId":%1}})").arg(node));
            m_inspected = node;
            emit stateChanged();
        }
        return;
    }
    if (!m_socket)
        return;
    if (id < 0) {
        m_socket->sendTextMessage(QString::fromUtf8(message));
        return;
    }
    const qint64 theirs = id - frontEnd;
    const QByteArray method = m_asked.take(theirs);
    const qsizetype digits = QByteArray::number(id).size();
    m_socket->sendTextMessage(QString::fromUtf8(QByteArray("{\"id\":") + QByteArray::number(theirs) + message.mid(6 + digits)));
    if (method == "DOM.getDocument" && !m_documentLoaded) {
        m_documentLoaded = true;
        emit stateChanged();
        if (m_inspect)
            inspectNow();
    }
}

void DevToolsBridge::inspectAt(QPointF point) {
    m_inspect = point;
    if (m_documentLoaded)
        inspectNow();
}

void DevToolsBridge::inspectNow() {
    const QPointF at = *std::exchange(m_inspect, std::nullopt);
    ownCall("DOM.getNodeForLocation", QByteArray("{\"x\":") + QByteArray::number(qRound(at.x())) + ",\"y\":" + QByteArray::number(qRound(at.y()))
                                          + ",\"includeUserAgentShadowDOM\":false,\"ignorePointerEventsNone\":true}");
}

void DevToolsBridge::ownCall(const QByteArray &method, const QByteArray &params) {
    if (!m_send)
        return;
    m_send("{\"id\":" + QByteArray::number(own + ++m_ownCalls) + ",\"method\":\"" + method + "\",\"params\":" + params + "}");
}
