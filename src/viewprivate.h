#pragma once

#include <QtGlobal>

class QPageLayout;
class QPageRanges;
class QQuickWebEngineView;
class QString;

// Qt 6.11's private API for a Qt Quick web view, in no installed header, declared here as Qt 6.11 has it
// (web_contents_adapter.h, qquickwebengineview_p_p.h, whose only base is WebContentsAdapterClient): recheck it after
// a Qt update. Windows.restore and Printing.toPdf use it.
namespace QtWebEngineCore {
class WebContentsAdapterClient;
class WebContentsAdapter;
}
class QQuickWebEngineViewPrivate {
public:
    bool adoptWebContents(QtWebEngineCore::WebContentsAdapter *webContents);
    // the override that QQuickWebEngineView::printToPdf calls with a zero-margin layout, no ranges and the frame -2
    // (WebContentsAdapter::kUseMainFrameId, read from its code); it answers with the view's pdfPrintingFinished
    void printToPdf(const QString &filePath, const QPageLayout &layout, const QPageRanges &ranges, quint64 frameId);
};

// the view's private (QQuickWebEngineView::d_ptr)
QQuickWebEngineViewPrivate *viewPrivate(QQuickWebEngineView *view);
