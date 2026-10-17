#pragma once

#include <QObject>
#include <QStringList>
#include <QTemporaryDir>
#include <QVariantList>
#include <QVariantMap>
#include <memory>
#include <qqmlintegration.h>

// Print (PLAN.md 3.16): a page as a PDF laid out as the print card says, which Qt Quick's printToPdf cannot do (it
// takes a paper size and an orientation only: no margins, no pages); the previews' files; the CUPS printers, and a
// PDF sent to one.
class Printing : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    using QObject::QObject;

    // --check-engine and --shots: these stand in for CUPS's printers, and a job is recorded (jobs()), never sent
    static inline QStringList fakePrinters;
    static inline bool dryRun = false;

    // WebEngineView `view`'s page as a PDF at `path`, laid out by `options`: { paper: "A4", "A3", "A5", "Letter" or
    // "Legal", landscape, margins (mm on every side), from, to (1-based pages; 0 for all) }. The view's
    // pdfPrintingFinished(path, success) answers. false when `view` is no web view.
    Q_INVOKABLE bool toPdf(QObject *view, const QString &path, const QVariantMap &options) const;
    // A new file name for a preview, in a folder of this run's under the temp dir, which goes when the browser quits.
    Q_INVOKABLE QString previewPath();
    Q_INVOKABLE void remove(const QString &path) const;
    // the size in bytes of the file at `path`, -1 for none
    Q_INVOKABLE qint64 size(const QString &path) const;
    // Asks CUPS for its printers off the UI thread; printersFound answers.
    Q_INVOKABLE void findPrinters();
    // The PDF at `path` sent to `printer` as a job named `title` on `paper` (CUPS's media), off the UI thread; sendDone
    // answers with the path and CUPS's error, "" when it took the job.
    Q_INVOKABLE void send(const QString &printer, const QString &path, const QString &title, const QString &paper);
    // check mode: the jobs recorded, { printer, path, title, paper, bytes }
    Q_INVOKABLE QVariantList jobs() const { return m_jobs; }

signals:
    void printersFound(const QStringList &names, const QString &defaultName);
    void sendDone(const QString &printer, const QString &path, const QString &error);

private:
    std::unique_ptr<QTemporaryDir> m_previews;
    int m_serial = 0;
    QVariantList m_jobs;
};
