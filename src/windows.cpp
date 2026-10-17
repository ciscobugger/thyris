#include "windows.h"
#include "viewprivate.h"
#ifdef BROWSER_CEF
#include "cef/pageitem.h"
#endif

#include <QByteArray>
#include <QDataStream>
#include <QGuiApplication>
#include <QIODevice>
#include <QSharedPointer>
#ifndef BROWSER_CEF
#include <QWebEngineHistory>
#include <QtWebEngineQuick/private/qquickwebengineview_p.h>
#endif

void Windows::showAs(QWindow *window, const QString &appId) {
    if (!window)
        return;
    const QString own = QGuiApplication::desktopFileName();
    // Backdrop leaves it out when it matches Hyprland's windows of the app's own class to ours
    window->setProperty("appId", appId);
    QGuiApplication::setDesktopFileName(appId.isEmpty() ? own : appId);
    window->show();
    QGuiApplication::setDesktopFileName(own);
}

#ifdef BROWSER_CEF
// CEF: the page's own (PageItem::historyData, restoreHistory; Opsis's CEF build carries the engine's half)
QString Windows::history(QObject *view) const {
    auto *page = qobject_cast<PageItem *>(view);
    return page ? page->historyData() : QString();
}
bool Windows::restore(QObject *view, const QString &history) const {
    auto *page = qobject_cast<PageItem *>(view);
    return page && page->restoreHistory(history);
}
#else
// WebEngineView's `history` property is the view's QWebEngineHistory
static QWebEngineHistory *historyOf(QObject *view) {
    return view ? qobject_cast<QWebEngineHistory *>(view->property("history").value<QObject *>()) : nullptr;
}

QString Windows::history(QObject *view) const {
    QWebEngineHistory *h = historyOf(view);
    if (!h)
        return {};
    QByteArray bytes;
    QDataStream out(&bytes, QIODevice::WriteOnly);
    out << *h;
    return QString::fromLatin1(bytes.toBase64());
}

// Qt 6.11's `stream >> history` casts the history's client to QWebEnginePagePrivate, and for a Qt Quick view that
// crashes (in setClient, measured). So restore() does for the view what it does for a page: the contents made from
// the stream (WebContentsAdapter), adopted as openIn adopts a new window's, then loaded. These are private and in no
// installed header, so they are declared here as Qt 6.11 has them (web_contents_adapter.h; the view's private is in
// viewprivate.h): recheck them after a Qt update.
namespace QtWebEngineCore {
class WebContentsAdapter {
public:
    static QSharedPointer<WebContentsAdapter> createFromSerializedNavigationHistory(QDataStream &input, WebContentsAdapterClient *adapterClient);
    void loadDefault();
};
}

// QQuickWebEngineView::d_ptr is private; an explicit instantiation may name it
template <typename Tag, typename Tag::type Member>
struct Expose {
    friend typename Tag::type member(Tag) { return Member; }
};
struct ViewPrivate {
    using type = QScopedPointer<QQuickWebEngineViewPrivate> QQuickWebEngineView::*;
    friend type member(ViewPrivate);
};
template struct Expose<ViewPrivate, &QQuickWebEngineView::d_ptr>;

QQuickWebEngineViewPrivate *viewPrivate(QQuickWebEngineView *view) { return (view->*member(ViewPrivate())).data(); }

bool Windows::restore(QObject *view, const QString &history) const {
    auto *quick = qobject_cast<QQuickWebEngineView *>(view);
    const QByteArray bytes = QByteArray::fromBase64(history.toLatin1());
    if (!quick || bytes.isEmpty())
        return false;
    QQuickWebEngineViewPrivate *d = viewPrivate(quick);
    QDataStream in(bytes);
    const QSharedPointer<QtWebEngineCore::WebContentsAdapter> contents =
        QtWebEngineCore::WebContentsAdapter::createFromSerializedNavigationHistory(in, reinterpret_cast<QtWebEngineCore::WebContentsAdapterClient *>(d));
    if (!contents || !d->adoptWebContents(contents.data()))
        return false;
    contents->loadDefault();
    return true;
}
#endif
