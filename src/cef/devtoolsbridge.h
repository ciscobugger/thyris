#pragma once

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QUrl>
#include <QVariantMap>
#include <QWebSocketServer>
#include <functional>
#include <optional>

class QWebSocket;

// DevTools for a page (PageItem::setDevToolsView, 2026-10-15). CEF draws no DevTools window off-screen under the Chrome
// runtime ("Windowless rendering is not supported for this DevTools window"), and Chromium's remote debugging port would
// open every page to every program on the computer. So Chromium's own DevTools front end loads as an ordinary page
// (devtools://devtools/bundled/devtools_app.html, as Chrome loads it for its own DevTools, can_dock for Chrome's docked
// controls, which Thyris's DevTools.js takes over) and speaks
// the DevTools protocol over a WebSocket to this relay, which hands it to the page through CEF (SendDevToolsMessage) and
// the page's answers and events back. It listens on 127.0.0.1 only, at a random port and a random path, takes one
// connection at a time from a devtools: page, and closes with DevTools.
// The page has one DevTools session in CEF, which Thyris's own calls share: the front end's message ids are moved past
// `frontEnd` on the way in and back on the way out, the relay's own past `own`.
// A spare (PageItem::prepareDevTools) is a relay with no page yet: its front end loads and connects, and what it says
// waits until bind() gives it a page, so DevTools opened on it show at once.
class DevToolsBridge : public QObject {
    Q_OBJECT
public:
    // Chromium takes an id that fits an int
    static constexpr qint64 frontEnd = qint64(1) << 29;
    static constexpr qint64 own = qint64(1) << 30;

    // `send`: a protocol message for the page (PageClient::sendDevTools); none for a spare, until bind()
    explicit DevToolsBridge(std::function<void(const QByteArray &)> send, QObject *parent = nullptr);
    void bind(std::function<void(const QByteArray &)> send);
    ~DevToolsBridge() override;
    QUrl frontEndUrl() const;
    // what the page said that is the front end's (an answer past frontEnd, or an event) or the relay's (past own);
    // `id` -1 for an event
    void fromPage(const QByteArray &message, qint64 id);
    // the element at `point` (the page's CSS px) shown in the Elements panel, once the front end has the document
    void inspectAt(QPointF point);
    // the message's id when it leads it, as Chromium writes answers ({"id":N,...}); -1 when it has none there
    static qint64 leadingId(const char *data, qsizetype size);
    // for the checks: { connected, document (the front end has the page's document), inspected (the last node shown) }
    QVariantMap state() const;
signals:
    void stateChanged();

private:
    void connected();
    void fromFrontEnd(const QString &message);
    void ownCall(const QByteArray &method, const QByteArray &params);
    void inspectNow();

    std::function<void(const QByteArray &)> m_send;
    QList<QByteArray> m_waiting;            // a spare's front end's calls, until it has a page
    QWebSocketServer m_server{QStringLiteral("Thyris DevTools"), QWebSocketServer::NonSecureMode};
    QPointer<QWebSocket> m_socket;
    QString m_token;
    QHash<qint64, QByteArray> m_asked;      // the front end's calls by id, kept until their answer, by method
    bool m_documentLoaded = false;          // the front end's DOM.getDocument answered: the Elements panel can reveal
    std::optional<QPointF> m_inspect;
    qint64 m_ownCalls = 0;
    int m_inspected = 0;
};
