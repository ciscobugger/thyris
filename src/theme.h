#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <qqmlintegration.h>

// The shell's colour and font sources, read the way Appearance.qml reads them, reloaded when matugen
// rewrites them: generated/colors.json (M3 roles), generated/terminal/sequences.txt (OSC 11, the
// terminal background used as window material), illogical-impulse/config.json (fonts, transparency,
// the wallpaper Frost.qml blurs).
class ThemeSource : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)
    Q_PROPERTY(QColor terminalBackground READ terminalBackground NOTIFY changed)
    Q_PROPERTY(QVariantMap fonts READ fonts NOTIFY changed)
    Q_PROPERTY(qreal contentTransparency READ contentTransparency NOTIFY changed)
    Q_PROPERTY(QUrl wallpaper READ wallpaper NOTIFY changed)
public:
    explicit ThemeSource(QObject *parent = nullptr);

    QVariantMap colors() const { return m_colors; }
    QColor terminalBackground() const { return m_terminal; }
    QVariantMap fonts() const { return m_fonts; }
    qreal contentTransparency() const { return m_contentTransparency; }
    QUrl wallpaper() const { return m_wallpaper; }

signals:
    void changed();

private:
    void reload();

    QString m_colorsPath, m_terminalPath, m_configPath;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QVariantMap m_colors, m_fonts;
    QColor m_terminal;
    qreal m_contentTransparency = 0.55;
    QUrl m_wallpaper;
};
