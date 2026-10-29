#pragma once

#include <QByteArray>
#include <QString>
#include <QUrl>
#include <functional>

// Downloads for the Chrome Web Store feature: https only, from Google's own hosts, redirects followed only to Google's own
// hosts, a size limit, no cookies and no stored login. The transport (the actual network) is a parameter so the rules can be
// tested with a stand-in.
namespace StoreFetch {

struct Reply {
    int status = 0;             // the HTTP status, 0 when none came
    QString location;           // the Location header of a redirect
    QByteArray body;
    bool tooBig = false;        // the body passed the limit and the transfer was stopped
    bool failed = false;        // no answer: no connection, a bad certificate, a timeout
};
using Transport = std::function<void(const QUrl &url, qint64 limit, std::function<void(Reply)> done)>;

// QNetworkAccessManager with no cookie jar, no cache, a stalled transfer given up after 30 s and any transfer after 3 minutes.
// A certificate that does not check out is a failure; nothing here ever ignores TLS errors.
Transport network();

inline constexpr int maxRedirects = 5;

// `done(body, "")` with the body of a 200 answer, else `done({}, why)`, in words for the person. Called once.
void get(const Transport &transport, const QUrl &url, qint64 limit, std::function<void(const QByteArray &body, const QString &problem)> done);

}
