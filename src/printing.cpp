#include "printing.h"
#ifdef BROWSER_CEF
#include "cef/pageitem.h"
#else
#include "viewprivate.h"
#endif

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMarginsF>
#include <QPageLayout>
#include <QPageRanges>
#include <QPageSize>
#include <QPointer>
#include <QThreadPool>
#ifndef BROWSER_CEF
#include <QtWebEngineQuick/private/qquickwebengineview_p.h>
#endif
#include <cups/cups.h>

bool Printing::toPdf(QObject *view, const QString &path, const QVariantMap &options) const {
#ifdef BROWSER_CEF
    // CEF's PrintToPDF takes the paper in inches as portrait and turns it for landscape; the page's backgrounds come from
    // its settings (PrintCard sets printElementBackgrounds), as Chromium reads them when Qt WebEngine prints
    auto *page = qobject_cast<PageItem *>(view);
    if (!page)
        return false;
    static const QHash<QString, QPageSize::PageSizeId> papers = {
        {QStringLiteral("A4"), QPageSize::A4}, {QStringLiteral("A3"), QPageSize::A3}, {QStringLiteral("A5"), QPageSize::A5},
        {QStringLiteral("Letter"), QPageSize::Letter}, {QStringLiteral("Legal"), QPageSize::Legal},
    };
    const QSizeF paper = QPageSize(papers.value(options.value(QStringLiteral("paper")).toString(), QPageSize::A4)).size(QPageSize::Inch);
    const QObject *settings = view->property("settings").value<QObject *>();
    page->printToPdf(path, paper, options.value(QStringLiteral("landscape")).toBool(),
                     options.value(QStringLiteral("margins")).toReal() / 25.4, options.value(QStringLiteral("from")).toInt(),
                     options.value(QStringLiteral("to")).toInt(), settings && settings->property("printElementBackgrounds").toBool());
    return true;
#else
    auto *quick = qobject_cast<QQuickWebEngineView *>(view);
    if (!quick)
        return false;
    static const QHash<QString, QPageSize::PageSizeId> papers = {
        {QStringLiteral("A4"), QPageSize::A4}, {QStringLiteral("A3"), QPageSize::A3}, {QStringLiteral("A5"), QPageSize::A5},
        {QStringLiteral("Letter"), QPageSize::Letter}, {QStringLiteral("Legal"), QPageSize::Legal},
    };
    const qreal m = options.value(QStringLiteral("margins")).toReal();
    const QPageLayout layout(QPageSize(papers.value(options.value(QStringLiteral("paper")).toString(), QPageSize::A4)),
                             options.value(QStringLiteral("landscape")).toBool() ? QPageLayout::Landscape : QPageLayout::Portrait,
                             QMarginsF(m, m, m, m), QPageLayout::Millimeter);
    QPageRanges ranges;
    const int from = options.value(QStringLiteral("from")).toInt(), to = options.value(QStringLiteral("to")).toInt();
    if (from > 0)
        ranges.addRange(from, qMax(from, to));
    viewPrivate(quick)->printToPdf(path, layout, ranges, quint64(-2));
    return true;
#endif
}

QString Printing::previewPath() {
    if (!m_previews)
        m_previews = std::make_unique<QTemporaryDir>(QDir::tempPath() + QStringLiteral("/browser-print-XXXXXX"));
    return m_previews->isValid() ? m_previews->filePath(QStringLiteral("preview-%1.pdf").arg(++m_serial)) : QString();
}

void Printing::remove(const QString &path) const {
    if (QFileInfo(path).isFile())
        QFile::remove(path);
}

qint64 Printing::size(const QString &path) const {
    const QFileInfo info(path);
    return info.isFile() ? info.size() : -1;
}

void Printing::findPrinters() {
    if (dryRun) {
        QMetaObject::invokeMethod(this, [this] { emit printersFound(fakePrinters, fakePrinters.value(0)); }, Qt::QueuedConnection);
        return;
    }
    const QPointer<Printing> self(this);
    // CUPS answers from its server, or after browsing the network for one: never on the UI thread
    QThreadPool::globalInstance()->start([self] {
        cups_dest_t *dests = nullptr;
        const int count = cupsGetDests2(CUPS_HTTP_DEFAULT, &dests);
        QStringList names;
        QString chosen;
        // a printer's instances (lpoptions' saved option sets) are left out: a job names the printer alone
        for (int i = 0; i < count; ++i) {
            if (dests[i].instance)
                continue;
            names.append(QString::fromUtf8(dests[i].name));
            if (dests[i].is_default)
                chosen = names.last();
        }
        cupsFreeDests(count, dests);
        QMetaObject::invokeMethod(self, [self, names, chosen] { if (self) emit self->printersFound(names, chosen); }, Qt::QueuedConnection);
    });
}

void Printing::send(const QString &printer, const QString &path, const QString &title, const QString &paper) {
    if (dryRun) {
        m_jobs.append(QVariantMap{{QStringLiteral("printer"), printer}, {QStringLiteral("path"), path}, {QStringLiteral("title"), title},
                                  {QStringLiteral("paper"), paper}, {QStringLiteral("bytes"), QFileInfo(path).size()}});
        QMetaObject::invokeMethod(this, [this, printer, path] { emit sendDone(printer, path, QString()); }, Qt::QueuedConnection);
        return;
    }
    const QPointer<Printing> self(this);
    QThreadPool::globalInstance()->start([self, printer, path, title, paper] {
        cups_option_t *options = nullptr;
        const int count = cupsAddOption("media", paper.toUtf8().constData(), 0, &options);
        const int job = cupsPrintFile2(CUPS_HTTP_DEFAULT, printer.toUtf8().constData(), QFile::encodeName(path).constData(),
                                       title.toUtf8().constData(), count, options);
        cupsFreeOptions(count, options);
        const QString error = job > 0 ? QString() : QString::fromUtf8(cupsLastErrorString());
        QMetaObject::invokeMethod(self, [self, printer, path, error] { if (self) emit self->sendDone(printer, path, error); }, Qt::QueuedConnection);
    });
}
