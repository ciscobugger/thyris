// The CEF page view's test window, run by tools/cef-page: one PageItem under a sheet of glass (CefPage.qml).
//   cefpage <url>
// Every 3 s it prints what the window drew (frames swapped, the worst gap between two, gaps over 25 ms) and the page's
// title, where the fixture pages write what they measured themselves. CEFPAGE_SECONDS=<n> ends it after n seconds,
// CEFPAGE_SHOT=<file.png> saves the window first, CEFPAGE_SWITCHES are Chromium's switches. CEFPAGE_SCROLL=<n>: from 3 s on,
// n seconds of a touchpad's steady scroll on the page (4 px down every 8 ms as a 125 Hz touchpad sends it, angleDelta 12x as
// Qt makes it); the report then also counts repeats, window frames drawn while it scrolled with no new page frame.
// CEFPAGE_REPLAY=<file>: from 3 s on, the scroll steps a hand made in Opsis (OPSIS_CEF_RECORD), at their own times.
#include "pageitem.h"
#include "runtime.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QDropEvent>
#include <QGuiApplication>
#include <QMimeData>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTimer>
#include <QWheelEvent>
#include <cstdio>
#include <memory>

int main(int argc, char *argv[]) {
    const QString data = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + QStringLiteral("/.cache"))
        + QStringLiteral("/opsis-cefpage");
    if (!CefRuntime::start(argc, argv, {data, qgetenv("CEFPAGE_SWITCHES")})) {
        std::fprintf(stderr, "cefpage: CEF did not start (its data dir is %s)\n", qPrintable(data));
        return 1;
    }
    // the render loop Opsis runs on (main.cpp)
    if (!qEnvironmentVariableIsSet("QSG_RENDER_LOOP"))
        qputenv("QSG_RENDER_LOOP", "basic");
    // the scene graph's GL context shares its textures with PageItem's
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QGuiApplication app(argc, argv);

    auto view = std::make_unique<QQuickView>();
    PageItem::registerQml(view->engine());
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->rootContext()->setContextProperty(QStringLiteral("startUrl"),
                                            QUrl::fromUserInput(app.arguments().value(1, QStringLiteral("about:blank"))));
    view->setSource(QUrl::fromLocalFile(QStringLiteral(CEFPAGE_QML)));
    view->resize(1920, 1080);
    view->show();
    auto *page = view->rootObject()->findChild<PageItem *>(QStringLiteral("page"));

    QElapsedTimer sinceSwap;
    // skipped: page frames that came and were replaced before the window drew (two or more between swaps)
    int swaps = 0, late = 0, pageFrames = 0, skipped = 0, seenAtSwap = 0, repeats = 0;
    bool scrolling = false;
    qint64 worst = 0;
    QObject::connect(view.get(), &QQuickWindow::frameSwapped, [&] {
        if (sinceSwap.isValid()) {
            const qint64 gap = sinceSwap.nsecsElapsed() / 1000;
            worst = qMax(worst, gap);
            late += gap > 25000;
        }
        sinceSwap.start();
        ++swaps;
        const int now = page->frames();
        skipped += qMax(0, now - seenAtSwap - 1);
        repeats += scrolling && now == seenAtSwap;
        seenAtSwap = now;
    });
    QTimer report;
    QObject::connect(&report, &QTimer::timeout, [&] {
        std::fprintf(stderr, "window: %.1f frames/s, worst gap %.1f ms, late %d, skipped %d, repeats %d | page: %.1f frames/s, %s | %s\n",
                     swaps / 3.0, worst / 1000.0, late, skipped, repeats, (page->frames() - pageFrames) / 3.0,
                     page->shared() ? "shared" : "through memory", qPrintable(page->title()));
        pageFrames = page->frames();
        swaps = late = skipped = repeats = 0;
        worst = 0;
        sinceSwap.invalidate();     // the gap across an idle stretch is not a late frame
    });
    report.start(3000);
    // CEFPAGE_DROP=<text>: after 3 s that text and this file are dropped in the page's middle, as another app's drag
    if (const QString drop = qEnvironmentVariable("CEFPAGE_DROP"); !drop.isEmpty())
        QTimer::singleShot(3000, page, [page, drop] {
            auto *mime = new QMimeData;
            mime->setText(drop);
            mime->setUrls({QUrl::fromLocalFile(QStringLiteral(CEFPAGE_QML))});
            const QPointF at(page->width() / 2, page->height() / 2);
            QDragEnterEvent enter(at.toPoint(), Qt::CopyAction, mime, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(page, &enter);
            QTimer::singleShot(300, page, [page, mime, at] {
                QDragMoveEvent move(at.toPoint(), Qt::CopyAction, mime, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::sendEvent(page, &move);
                QTimer::singleShot(300, page, [page, mime, at] {
                    QDropEvent dropped(at, Qt::CopyAction, mime, Qt::NoButton, Qt::NoModifier);
                    QCoreApplication::sendEvent(page, &dropped);
                    std::fprintf(stderr, "drop sent (accepted: %d)\n", dropped.isAccepted());
                });
            });
        });
    if (const int seconds = qEnvironmentVariableIntValue("CEFPAGE_SCROLL"))
        QTimer::singleShot(3000, page, [page, seconds, &scrolling] {
            auto *timer = new QTimer(page);
            auto *clock = new QElapsedTimer;
            clock->start();
            timer->setTimerType(Qt::PreciseTimer);
            QObject::connect(timer, &QTimer::timeout, page, [page, seconds, timer, clock, &scrolling] {
                const bool end = clock->elapsed() > seconds * 1000;
                const Qt::ScrollPhase phase = !scrolling ? Qt::ScrollBegin : end ? Qt::ScrollEnd : Qt::ScrollUpdate;
                const QPointF at(page->width() / 2, page->height() / 2);
                const QPoint pixels(0, end ? 0 : -4);
                QWheelEvent wheel(at, page->mapToGlobal(at), pixels, pixels * 12, Qt::NoButton, Qt::NoModifier, phase, false);
                QCoreApplication::sendEvent(page, &wheel);
                scrolling = !end;
                if (end)
                    timer->stop();
            });
            timer->start(8);
        });
    if (const QString replay = qEnvironmentVariable("CEFPAGE_REPLAY"); !replay.isEmpty())
        QTimer::singleShot(3000, page, [page, replay, &scrolling] {
            struct Step { qint64 at; int phase; QPoint pixels, angle; };
            auto *steps = new QList<Step>;
            QFile file(replay);
            if (file.open(QIODevice::ReadOnly))
                for (const QByteArray &line : file.readAll().split('\n')) {
                    const QList<QByteArray> f = line.split(' ');
                    if (f.size() == 6)
                        steps->append({f[0].toLongLong(), f[1].toInt(), {f[2].toInt(), f[3].toInt()}, {f[4].toInt(), f[5].toInt()}});
                }
            std::fprintf(stderr, "replay: %lld steps over %.1f s\n", (long long)steps->size(),
                         steps->isEmpty() ? 0.0 : (steps->last().at - steps->first().at) / 1e9);
            auto *clock = new QElapsedTimer;
            clock->start();
            auto *timer = new QTimer(page);
            timer->setTimerType(Qt::PreciseTimer);
            auto *next = new int(0);
            QObject::connect(timer, &QTimer::timeout, page, [=, &scrolling] {
                const qint64 now = clock->nsecsElapsed();
                while (*next < steps->size() && (*steps)[*next].at - steps->first().at <= now) {
                    const Step &st = (*steps)[(*next)++];
                    const QPointF at(page->width() / 2, page->height() / 2);
                    QWheelEvent wheel(at, page->mapToGlobal(at), st.pixels, st.angle, Qt::NoButton, Qt::NoModifier,
                                      Qt::ScrollPhase(st.phase), false);
                    QCoreApplication::sendEvent(page, &wheel);
                    scrolling = true;
                }
                if (*next >= steps->size()) {
                    scrolling = false;
                    timer->stop();
                }
            });
            timer->start(1);
        });
    if (const int seconds = qEnvironmentVariableIntValue("CEFPAGE_SECONDS"))
        QTimer::singleShot(seconds * 1000, [&] {
            const QString shot = qEnvironmentVariable("CEFPAGE_SHOT");
            if (!shot.isEmpty())
                view->grabWindow().save(shot);
            app.quit();
        });

    const int result = app.exec();
    view.reset();           // the page closes with its item, before CEF stops
    CefRuntime::stop();
    return result;
}
