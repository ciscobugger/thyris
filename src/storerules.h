#pragma once

#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QUrl>

// The rules of the Chrome Web Store feature that need no network, kept apart so they can be tested alone
// (tests/native/store_test.cpp): which pages offer Add, where a file may come from, and what an extension can do, in words.
namespace StoreRules {

// The id (32 letters a-p) of the extension whose store page `page` is, else "". Only an item's own page counts: the store's
// address https://chromewebstore.google.com/detail/<name>/<id> or the old https://chrome.google.com/webstore/detail/<name>/<id>,
// with the default port, no user name, and the query and fragment ignored.
QString itemId(const QUrl &page);
bool validId(const QString &id);

// Google's own hosts over https only: *.google.com, *.googleusercontent.com, *.gvt1.com, the default port, no user name.
bool googleAddress(const QUrl &url);
// Where a redirect to `location` (absolute, or relative to `from`) leads, or an empty QUrl when it is not allowed
QUrl nextHop(const QUrl &from, const QString &location);

// Chrome's update service. The first answers with a redirect to the file; the second with an XML answer that names the
// newest version and where its file is (nothing is sent but the id, the versions and the answer's format).
QUrl fileUrl(const QString &id, const QString &prodVersion);
QUrl updateCheckUrl(const QString &id, const QString &prodVersion, const QString &haveVersion);

struct UpdateAnswer {
    bool ok = false;        // an answer for `id` was read
    bool newer = false;     // there is a version newer than the one given
    QString version;
    QUrl file;
    QString sha256;         // hex, when the answer gave one
};
UpdateAnswer parseUpdateCheck(const QByteArray &xml, const QString &id, const QString &haveVersion);
bool versionNewer(const QString &a, const QString &b);

// What the extension can do, in plain words, most far-reaching first: the reach of its manifest's permissions,
// host_permissions and content scripts. Empty for one that asks for nothing of note.
QStringList permissionWords(const QJsonObject &manifest);
// The words for what `now` can do that `before` could not (an update that asks for more), empty when it asks for nothing new
QStringList addedWords(const QJsonObject &before, const QJsonObject &now);

}
