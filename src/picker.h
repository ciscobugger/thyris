#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <qqmlintegration.h>

class QProcess;

// File inputs pick in the shell's Files window (PLAN.md 3.8 8l): `qs -c tacit ipc call files pick <folder>
// <shell> <target> <label>` opens one with a Choose bar, and Choose hands the paths back over Quickshell IPC
// (`qs -p <shell> ipc call <target> picked <json>`). The browser is no Quickshell instance, so a relay shell
// (one IpcHandler) runs for the length of a pick and prints what it is handed. Files says nothing when a
// pick ends without a choice, so a pick is over once the browser is active again and no choice has come
// within 1 s, or when the browser has not lost the focus to Files within 5 s.
class Picker : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString label READ label NOTIFY busyChanged)
public:
    explicit Picker(QObject *parent = nullptr);

    // --check-engine: nothing runs; answer() plays Files' part
    static inline bool dryRun = false;

    // Opens Files for one pick; false while another pick is open.
    Q_INVOKABLE bool pick(const QString &label);
    // Check mode: Choose with `paths`, or Cancel with none.
    Q_INVOKABLE void answer(const QStringList &paths);
    // Ends the pick with nothing chosen, for a page that no longer waits on it. Files stays open (it takes
    // no close over IPC), and what it hands back later goes nowhere.
    Q_INVOKABLE void cancel() { end({}); }
    bool busy() const { return m_busy; }
    QString label() const { return m_label; }

signals:
    // what was chosen; nothing when the pick ended without a choice
    void finished(const QStringList &paths);
    void busyChanged();

private:
    void end(const QStringList &paths);
    void readRelay();

    QProcess *m_relay = nullptr;
    QTimer m_grace, m_watch;
    QString m_label;
    bool m_busy = false;
    bool m_away = false;
    int m_serial = 0;
};
