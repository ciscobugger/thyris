#include "shots.h"

#include <QCoreApplication>
#include <QDir>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QQmlApplicationEngine>
#ifdef BROWSER_CEF
#include "cef/pageitem.h"
#endif
#include <QQuickWindow>
#include <QUrl>
#include <cstdio>

Shots::Shots(const QString &outDir, const QStringList &requested, const QString &dataDir)
    : m_outDir(outDir), m_dataDir(dataDir), m_queue(requested), m_discover(requested.isEmpty()) {
    m_watchdog.setSingleShot(true);
    m_watchdog.setInterval(20000);
    connect(&m_watchdog, &QTimer::timeout, this, [this] { fail(QStringLiteral("timed out")); });
}

void Shots::start() {
    QDir().mkpath(m_outDir);
    if (!m_discover)
        m_current = m_queue.takeFirst();
    load();
}

void Shots::load() {
    m_engine = new QQmlApplicationEngine(this);
#ifdef BROWSER_CEF
    PageItem::registerQml(m_engine);
#endif
    m_engine->setInitialProperties({
        {QStringLiteral("dataDir"), m_dataDir},
        {QStringLiteral("startUrl"), QUrl()},
        {QStringLiteral("adblock"), QVariant::fromValue<QObject *>(nullptr)},
        {QStringLiteral("shots"), QVariant::fromValue<QObject *>(this)},
        // the window size of a tiled window on this laptop's 1920x1080 screen
        {QStringLiteral("width"), 1908},
        {QStringLiteral("height"), 1030},
    });
    connect(m_engine, &QQmlApplicationEngine::objectCreationFailed, this,
            [this] { fail(QStringLiteral("Main failed to load")); }, Qt::QueuedConnection);
    m_watchdog.start();
    m_engine->loadFromModule("Browser", "Main");
}

QString Shots::begin(const QStringList &known) {
    if (m_discover) {
        m_discover = false;
        m_queue = known;
        m_current = m_queue.takeFirst();
    }
    if (!known.contains(m_current)) {
        fail(QStringLiteral("unknown scenario; known: ") + known.join(u' '));
        return {};
    }
    return m_current;
}

void Shots::capture(const QString &name, QObject *other) {
    auto *window = qobject_cast<QQuickWindow *>(other);
    if (!window && m_engine)
        window = qobject_cast<QQuickWindow *>(m_engine->rootObjects().value(0));
    const QString path = QDir(m_outDir).absoluteFilePath(name + QStringLiteral(".png"));
    if (!window || !window->grabWindow().save(path)) {
        fail(QStringLiteral("could not grab or save ") + path);
        return;
    }
    std::printf("%s\n", qPrintable(path));
    std::fflush(stdout);
    QTimer::singleShot(0, this, &Shots::next);
}

void Shots::render() {
    if (auto *window = m_engine ? qobject_cast<QQuickWindow *>(m_engine->rootObjects().value(0)) : nullptr)
        window->grabWindow();
}

void Shots::fail(const QString &message) {
    std::fprintf(stderr, "shots: %s: %s\n", qPrintable(m_current), qPrintable(message));
    m_failures++;
    QTimer::singleShot(0, this, &Shots::next);
}

void Shots::next() {
    m_watchdog.stop();
    if (m_engine) {
        m_engine->deleteLater();
        m_engine = nullptr;
    }
    if (m_queue.isEmpty()) {
        QCoreApplication::exit(m_failures > 0 ? 1 : 0);
        return;
    }
    m_current = m_queue.takeFirst();
    // after the old engine and its window are gone
    QTimer::singleShot(0, this, &Shots::load);
}

QString Shots::samplePdf(const QString &name, const QString &title, const QStringList &lines, int pages) {
    const QString path = QDir(m_dataDir).absoluteFilePath(name);
    QDir().mkpath(m_dataDir);
    QPdfWriter writer(path);
    writer.setPageSize(QPageSize(QPageSize::A4));
    writer.setPageMargins(QMarginsF(15, 15, 15, 15), QPageLayout::Millimeter);
    writer.setResolution(72);
    QPainter p(&writer);
    const QRect area = p.viewport();
    QFont body(QStringLiteral("sans-serif"));
    body.setPixelSize(11);
    QFont head = body;
    head.setPixelSize(20);
    head.setBold(true);
    for (int page = 0; page < pages; ++page) {
        if (page > 0)
            writer.newPage();
        int y = 0;
        if (page == 0) {
            p.setFont(head);
            const QRect r = p.boundingRect(QRect(0, 0, area.width(), 200), Qt::TextWordWrap, title);
            p.drawText(r, Qt::TextWordWrap, title);
            y = r.bottom() + 16;
        }
        p.setFont(body);
        for (int i = 0; y < area.height() - 20; ++i) {
            const QString line = lines.value(i % qMax(1, lines.size()));
            const QRect r = p.boundingRect(QRect(0, y, area.width(), 200), Qt::TextWordWrap, line);
            p.drawText(r, Qt::TextWordWrap, line);
            y = r.bottom() + 6;
        }
    }
    return path;
}
