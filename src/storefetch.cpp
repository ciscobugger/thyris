#include "storefetch.h"

#include "storerules.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <QTimer>
#include <memory>

StoreFetch::Transport StoreFetch::network() {
    return [](const QUrl &url, qint64 limit, std::function<void(Reply)> done) {
        static QNetworkAccessManager *manager = [] {
            auto *m = new QNetworkAccessManager;
            m->setCookieJar(nullptr);
            return m;
        }();
        QNetworkRequest request(url);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
        request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
        request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
        request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, false);
        request.setAttribute(QNetworkRequest::AuthenticationReuseAttribute, QNetworkRequest::Manual);
        request.setTransferTimeout(30000);
        request.setRawHeader("User-Agent", "Thyris");
        QNetworkReply *reply = manager->get(request);
        auto body = std::make_shared<QByteArray>();
        auto big = std::make_shared<bool>(false);
        QObject::connect(reply, &QNetworkReply::readyRead, reply, [reply, body, big, limit] {
            body->append(reply->readAll());
            if (body->size() > limit && !*big) {
                *big = true;
                reply->abort();
            }
        });
        QObject::connect(reply, &QNetworkReply::metaDataChanged, reply, [reply, big, limit] {
            const qint64 declared = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
            if (declared > limit && !*big) {
                *big = true;
                reply->abort();
            }
        });
        QTimer::singleShot(180000, reply, [reply] { reply->abort(); });
        QObject::connect(reply, &QNetworkReply::finished, reply, [reply, body, big, done] {
            Reply out;
            out.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            out.location = QString::fromLatin1(reply->rawHeader("Location"));
            out.tooBig = *big;
            out.body = std::move(*body);
            out.body.append(reply->readAll());
            out.failed = out.status == 0 && !out.tooBig;
            reply->deleteLater();
            done(out);
        });
    };
}

namespace {

struct Walk : std::enable_shared_from_this<Walk> {
    StoreFetch::Transport transport;
    qint64 limit;
    std::function<void(const QByteArray &, const QString &)> done;
    int hops = 0;

    void go(const QUrl &url) {
        auto self = shared_from_this();
        transport(url, limit, [self, url](StoreFetch::Reply r) { self->arrived(url, r); });
    }
    void arrived(const QUrl &url, const StoreFetch::Reply &r) {
        if (r.tooBig)
            return done({}, QObject::tr("The extension file is too big, so nothing was added."));
        if (r.failed)
            return done({}, QObject::tr("Thyris couldn't reach Google's extension service. Check your connection and try again."));
        if (r.status == 301 || r.status == 302 || r.status == 303 || r.status == 307 || r.status == 308) {
            const QUrl next = StoreRules::nextHop(url, r.location);
            if (next.isEmpty())
                return done({}, QObject::tr("Google's extension service sent Thyris somewhere it doesn't trust, so nothing was added."));
            if (++hops > StoreFetch::maxRedirects)
                return done({}, QObject::tr("Google's extension service sent Thyris round in circles, so nothing was added."));
            return go(next);
        }
        if (r.status == 200)
            return done(r.body, QString());
        if (r.status == 404)
            return done({}, QObject::tr("Google has no extension at that address."));
        done({}, QObject::tr("Google's extension service didn't give the file (error %1).").arg(r.status));
    }
};

}

void StoreFetch::get(const Transport &transport, const QUrl &url, qint64 limit,
                     std::function<void(const QByteArray &, const QString &)> done) {
    if (!StoreRules::googleAddress(url))
        return done({}, QObject::tr("That address is not one of Google's, so nothing was fetched."));
    auto walk = std::make_shared<Walk>();
    walk->transport = transport;
    walk->limit = limit;
    walk->done = std::move(done);
    walk->go(url);
}
