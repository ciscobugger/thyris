#pragma once

#include <QDir>
#include <QString>
#include <QStringList>

// `qs` reaches Tacit's shell by the folder it runs from: an install's shell runs as /usr/share/tacit/shell (TACIT_SHELL,
// set by the session), the owner's as ~/.config/quickshell/tacit. `qs -c tacit` names /etc/xdg/quickshell/tacit, which
// an install's shell does not answer to, and every pick, sign-in in the notch and Show in Files failed there
// (2026-10-20, Discord: no files could be added to a page).
inline QStringList shellIpc() {
    const QString shell = qEnvironmentVariableIsEmpty("TACIT_SHELL") ? QDir::homePath() + QStringLiteral("/.config/quickshell/tacit")
                                                                      : qEnvironmentVariable("TACIT_SHELL");
    return {QStringLiteral("-p"), shell, QStringLiteral("ipc"), QStringLiteral("call")};
}
