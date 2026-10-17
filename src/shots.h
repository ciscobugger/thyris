#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>

class QQmlApplicationEngine;

// `browser --shots <outdir> [scenario ...]`: renders named UI states offscreen to <outdir>/<name>.png,
// one fresh QML engine per scenario so no state leaks between them. Shots.qml owns the scenario list,
// seeds a fake session and calls capture() once the state has settled. No web views are created.
class Shots : public QObject {
    Q_OBJECT
public:
    Shots(const QString &outDir, const QStringList &requested, const QString &dataDir);

    void start();
    // The scenario this engine renders, given the ones Shots.qml knows; "" when the name is unknown.
    Q_INVOKABLE QString begin(const QStringList &known);
    // Grabs `window` (a window the first one made, PLAN.md 3.17), else the first window.
    Q_INVOKABLE void capture(const QString &name, QObject *window = nullptr);
    Q_INVOKABLE void fail(const QString &message);
    // A PDF named `name` of `pages` A4 pages for the print card's preview (PLAN.md 3.16), as a page would print: `title`
    // over `lines` on the first, `lines` on the rest. Its path, in the throwaway data dir.
    Q_INVOKABLE QString samplePdf(const QString &name, const QString &title, const QStringList &lines, int pages);

private:
    void load();
    void next();

    QString m_outDir, m_dataDir, m_current;
    QStringList m_queue;
    bool m_discover = false;    // no names given: render every scenario Shots.qml knows
    int m_failures = 0;
    QQmlApplicationEngine *m_engine = nullptr;
    QTimer m_watchdog;
};
