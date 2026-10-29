// Tests of the Chrome Web Store feature's parts that need no window or network: the CRX3 verifier, the zip unpacker, and the
// store's rules. The test files are made here: a key generated per run, a CRX built and signed in the real format
// (https://chromium.googlesource.com/chromium/src/+/main/components/crx_file/crx3.proto), then tampered in each way.
// CRX_FILE=<a real .crx> CRX_ID=<its id> adds a check of a file Google served (kept out of the repo).
#include "crx.h"
#include "extensions.h"
#include "storefetch.h"
#include "storerules.h"
#include "webstore.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QtEndian>
#include <QSignalSpy>
#include <QtTest>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <zlib.h>

using namespace Qt::StringLiterals;

namespace {

struct Key {
    EVP_PKEY *pkey = nullptr;
    bool ecdsa = false;
    QByteArray der() const {
        uchar *out = nullptr;
        const int n = i2d_PUBKEY(pkey, &out);
        const QByteArray b(reinterpret_cast<const char *>(out), n);
        OPENSSL_free(out);
        return b;
    }
};
Key rsa(int bits = 2048) {
    Key k;
    k.pkey = EVP_RSA_gen(bits);
    return k;
}
Key ec() {
    Key k;
    k.pkey = EVP_EC_gen("P-256");
    k.ecdsa = true;
    return k;
}

QByteArray sign(const Key &k, const QByteArray &data) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestSignInit(ctx, nullptr, EVP_sha256(), nullptr, k.pkey);
    EVP_DigestSignUpdate(ctx, data.constData(), size_t(data.size()));
    size_t n = 0;
    EVP_DigestSignFinal(ctx, nullptr, &n);
    QByteArray sig(int(n), 0);
    EVP_DigestSignFinal(ctx, reinterpret_cast<uchar *>(sig.data()), &n);
    sig.resize(int(n));
    EVP_MD_CTX_free(ctx);
    return sig;
}

// protobuf
QByteArray varint(quint64 v) {
    QByteArray out;
    do {
        uchar b = v & 0x7f;
        v >>= 7;
        out.append(char(b | (v ? 0x80 : 0)));
    } while (v);
    return out;
}
QByteArray field(quint32 number, const QByteArray &bytes) { return varint((quint64(number) << 3) | 2) + varint(quint64(bytes.size())) + bytes; }

QByteArray idBytes(const QByteArray &der) {
    uchar digest[32];
    unsigned len = 0;
    EVP_Digest(der.constData(), size_t(der.size()), digest, &len, EVP_sha256(), nullptr);
    return QByteArray(reinterpret_cast<const char *>(digest), 16);
}

// the pieces of a CRX, kept apart so a test can change one
struct Parts {
    QByteArray archive;
    QByteArray signedData;                  // SignedData { crx_id }
    QList<QPair<Key, bool>> signers;        // keys that sign (bool unused)
    QList<QByteArray> proofKeys, proofSigs; // filled by build
};

// JSON written with single quotes
QByteArray J(const char *s) { return QByteArray(s).replace('\'', '"'); }

QByteArray signedDataFor(const Key &publisher) { return field(1, idBytes(publisher.der())); }

QByteArray toSign(const QByteArray &signedData, const QByteArray &archive) {
    QByteArray size(4, 0);
    qToLittleEndian<quint32>(quint32(signedData.size()), size.data());
    return QByteArray("CRX3 SignedData\0", 16) + size + signedData + archive;
}

QByteArray crxFrom(const QByteArray &header, const QByteArray &archive, quint32 version = 3) {
    QByteArray out("Cr24");
    QByteArray n(4, 0);
    qToLittleEndian<quint32>(version, n.data());
    out += n;
    qToLittleEndian<quint32>(quint32(header.size()), n.data());
    return out + n + header + archive;
}

// a CRX signed by every key in `signers`, naming `publisher`'s id
QByteArray buildCrx(const QByteArray &archive, const Key &publisher, const QList<Key> &signers) {
    const QByteArray signedData = signedDataFor(publisher);
    QByteArray header;
    for (const Key &k : signers) {
        const QByteArray proof = field(1, k.der()) + field(2, sign(k, toSign(signedData, archive)));
        header += field(k.ecdsa ? 3 : 2, proof);
    }
    header += field(10000, signedData);
    return crxFrom(header, archive);
}

QString idOf(const Key &k) { return Crx::idOfKey(k.der()); }

// a zip
struct ZipEntry {
    QString name;
    QByteArray data;
    bool deflate = true;
    quint32 unixMode = 0100644;
    quint16 flags = 0;
    quint32 declaredSize = 0xffffffff;      // 0xffffffff: the real one
    quint32 crcOverride = 0;
    bool overrideCrc = false;
};
QByteArray le16(quint16 v) { QByteArray b(2, 0); qToLittleEndian(v, b.data()); return b; }
QByteArray le32(quint32 v) { QByteArray b(4, 0); qToLittleEndian(v, b.data()); return b; }
QByteArray makeZip(const QList<ZipEntry> &entries) {
    QByteArray body, central;
    for (const ZipEntry &e : entries) {
        const bool dir = e.name.endsWith(u'/');
        QByteArray packed = e.data;
        quint16 method = 0;
        if (e.deflate && !dir) {
            z_stream z{};
            deflateInit2(&z, 9, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
            packed.resize(int(deflateBound(&z, uLong(e.data.size()))));
            z.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(e.data.constData()));
            z.avail_in = uInt(e.data.size());
            z.next_out = reinterpret_cast<Bytef *>(packed.data());
            z.avail_out = uInt(packed.size());
            deflate(&z, Z_FINISH);
            packed.resize(int(z.total_out));
            deflateEnd(&z);
            method = 8;
        }
        const quint32 crc = e.overrideCrc ? e.crcOverride : quint32(crc32(0, reinterpret_cast<const Bytef *>(e.data.constData()), uInt(e.data.size())));
        const quint32 usize = e.declaredSize == 0xffffffff ? quint32(e.data.size()) : e.declaredSize;
        const QByteArray name = e.name.toUtf8();
        const quint32 offset = quint32(body.size());
        body += le32(0x04034b50) + le16(20) + le16(e.flags) + le16(method) + le16(0) + le16(0x21) + le32(crc) + le32(quint32(packed.size()))
                + le32(usize) + le16(quint16(name.size())) + le16(0) + name + packed;
        central += le32(0x02014b50) + le16(quint16((3 << 8) | 20)) + le16(20) + le16(e.flags) + le16(method) + le16(0) + le16(0x21) + le32(crc)
                   + le32(quint32(packed.size())) + le32(usize) + le16(quint16(name.size())) + le16(0) + le16(0) + le16(0) + le16(0)
                   + le32(e.unixMode << 16) + le32(offset) + name;
    }
    const QByteArray end = le32(0x06054b50) + le16(0) + le16(0) + le16(quint16(entries.size())) + le16(quint16(entries.size()))
                           + le32(quint32(central.size())) + le32(quint32(body.size())) + le16(0);
    return body + central + end;
}

QByteArray goodZip() {
    return makeZip({{QStringLiteral("manifest.json"), J("{'manifest_version':3,'name':'T','version':'1.0'}")},
                    {QStringLiteral("icons/"), {}, false, 040755},
                    {QStringLiteral("icons/16.png"), QByteArray(300, 'x'), false},
                    {QStringLiteral("js/background.js"), QByteArray("console.log(1);\n").repeated(200)}});
}

StoreFetch::Reply redirect(const QString &to) {
    StoreFetch::Reply r;
    r.status = 302;
    r.location = to;
    return r;
}
StoreFetch::Reply body(const QByteArray &b) {
    StoreFetch::Reply r;
    r.status = 200;
    r.body = b;
    return r;
}
// a network that answers from a table and notes what was asked of it
StoreFetch::Transport scripted(QHash<QString, StoreFetch::Reply> table, QStringList *seen) {
    return [table, seen](const QUrl &url, qint64, std::function<void(StoreFetch::Reply)> done) {
        if (seen)
            seen->append(url.toString());
        StoreFetch::Reply r;
        r.failed = !table.contains(url.toString());
        done(table.value(url.toString(), r));
    };
}

}

class StoreTest : public QObject {
    Q_OBJECT
private slots:
    // ---- CRX3
    void validRsa() {
        const Key k = rsa();
        const QByteArray zip = goodZip();
        const auto r = Crx::verify(buildCrx(zip, k, {k}), idOf(k));
        QVERIFY2(r.ok, qPrintable(r.problem));
        QCOMPARE(r.id, idOf(k));
        QCOMPARE(r.key, k.der());
        QCOMPARE(r.zip, zip);
        QCOMPARE(r.id.size(), 32);
        for (const QChar c : r.id)
            QVERIFY(c >= u'a' && c <= u'p');
    }
    void validWithStoreProofAndEcdsa() {
        const Key publisher = rsa(), store = rsa(), ecKey = ec();
        const auto r = Crx::verify(buildCrx(goodZip(), publisher, {store, publisher, ecKey}), idOf(publisher));
        QVERIFY2(r.ok, qPrintable(r.problem));
        QCOMPARE(r.key, publisher.der());
    }
    void idIsKeyHash() {
        // the id of a key is the first 16 bytes of its SHA-256 written with a-p: known vector, the nibbles of 0x00 0xff 0x1a ...
        QCOMPARE(Crx::idOfKey(QByteArray()), QString());
        const Key k = rsa();
        QCOMPARE(Crx::idOfKey(k.der()).size(), 32);
        QVERIFY(Crx::idOfKey(k.der()) != Crx::idOfKey(rsa().der()));
    }
    void wrongIdRefused() {
        const Key k = rsa(), other = rsa();
        const auto r = Crx::verify(buildCrx(goodZip(), k, {k}), idOf(other));
        QVERIFY(!r.ok);
        QVERIFY(r.problem.contains(u"different extension"));
    }
    void flippedArchiveByteRefused() {
        const Key k = rsa();
        QByteArray crx = buildCrx(goodZip(), k, {k});
        crx[crx.size() - 30] = char(crx.at(crx.size() - 30) ^ 1);
        const auto r = Crx::verify(crx, idOf(k));
        QVERIFY(!r.ok);
        QVERIFY(r.problem.contains(u"check out"));
    }
    void everyByteOfTheTailMatters() {
        // a flip in any of 40 spread positions of the file (header, signature, archive) is refused
        const Key k = rsa();
        const QByteArray crx = buildCrx(goodZip(), k, {k});
        for (int i = 0; i < 40; ++i) {
            QByteArray bad = crx;
            const int at = 12 + (i * (crx.size() - 12)) / 40;
            bad[at] = char(bad.at(at) ^ 0x40);
            QVERIFY2(!Crx::verify(bad, idOf(k)).ok, qPrintable(QStringLiteral("flip at %1 was accepted").arg(at)));
        }
    }
    void archiveSwappedForAnotherRefused() {
        const Key k = rsa();
        const QByteArray crx = buildCrx(goodZip(), k, {k});
        const qint64 headerSize = qFromLittleEndian<quint32>(crx.constData() + 8);
        const QByteArray evil = makeZip({{QStringLiteral("manifest.json"), J("{'manifest_version':3,'name':'Evil','version':'9'}")}});
        const QByteArray swapped = crx.left(int(12 + headerSize)) + evil;
        QVERIFY(!Crx::verify(swapped, idOf(k)).ok);
    }
    void signedDataForAnotherKeyRefused() {
        // names the victim's id, signed by the attacker's key: the proof holds, but no proof is by the victim's key
        const Key attacker = rsa(), victim = rsa();
        const QByteArray zip = goodZip();
        const QByteArray signedData = signedDataFor(victim);
        const QByteArray proof = field(1, attacker.der()) + field(2, sign(attacker, toSign(signedData, zip)));
        const QByteArray crx = crxFrom(field(2, proof) + field(10000, signedData), zip);
        const auto r = Crx::verify(crx, idOf(victim));
        QVERIFY(!r.ok);
        QVERIFY(r.problem.contains(u"maker"));
    }
    void signatureOfOtherDataRefused() {
        const Key k = rsa();
        const QByteArray zip = goodZip();
        const QByteArray signedData = signedDataFor(k);
        const QByteArray proof = field(1, k.der()) + field(2, sign(k, QByteArrayLiteral("something else")));
        QVERIFY(!Crx::verify(crxFrom(field(2, proof) + field(10000, signedData), zip), idOf(k)).ok);
    }
    void oneBadProofAmongGoodRefused() {
        const Key k = rsa(), store = rsa();
        const QByteArray zip = goodZip();
        const QByteArray signedData = signedDataFor(k);
        const QByteArray good = field(1, k.der()) + field(2, sign(k, toSign(signedData, zip)));
        const QByteArray bad = field(1, store.der()) + field(2, QByteArray(256, 'z'));
        QVERIFY(!Crx::verify(crxFrom(field(2, good) + field(2, bad) + field(10000, signedData), zip), idOf(k)).ok);
    }
    void smallRsaKeyRefused() {
        const Key weak = rsa(1024);
        const auto r = Crx::verify(buildCrx(goodZip(), weak, {weak}), idOf(weak));
        QVERIFY(!r.ok);
    }
    void keyTypeInWrongListRefused() {
        // an ecdsa key listed as an rsa proof
        const Key k = ec();
        const QByteArray zip = goodZip();
        const QByteArray signedData = signedDataFor(k);
        const QByteArray proof = field(1, k.der()) + field(2, sign(k, toSign(signedData, zip)));
        QVERIFY(!Crx::verify(crxFrom(field(2, proof) + field(10000, signedData), zip), idOf(k)).ok);
    }
    void noProofsRefused() {
        const Key k = rsa();
        QVERIFY(!Crx::verify(crxFrom(field(10000, signedDataFor(k)), goodZip()), idOf(k)).ok);
    }
    void malformedFilesRefused() {
        const Key k = rsa();
        const QByteArray crx = buildCrx(goodZip(), k, {k});
        QVERIFY(!Crx::verify(QByteArray(), idOf(k)).ok);
        QVERIFY(!Crx::verify(crx.left(7), idOf(k)).ok);
        QVERIFY(!Crx::verify(crx.left(40), idOf(k)).ok);                       // header cut short
        QVERIFY(!Crx::verify("PK" + crx.mid(2), idOf(k)).ok);                   // not Cr24
        QVERIFY(!Crx::verify(crxFrom(QByteArray(10, 'a'), goodZip(), 2), idOf(k)).ok);   // version 2
        QByteArray huge = crx;
        qToLittleEndian<quint32>(0x7fffffff, huge.data() + 8);
        QVERIFY(!Crx::verify(huge, idOf(k)).ok);
        QByteArray noise = crx.left(12);
        noise += QByteArray(200, char(0xff));                                  // a varint that never ends
        qToLittleEndian<quint32>(200, noise.data() + 8);
        QVERIFY(!Crx::verify(noise, idOf(k)).ok);
    }
    void realFile() {
        const QByteArray path = qgetenv("CRX_FILE"), id = qgetenv("CRX_ID");
        if (path.isEmpty() || id.isEmpty())
            QSKIP("CRX_FILE and CRX_ID not set");
        QFile f(QString::fromLocal8Bit(path));
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QByteArray crx = f.readAll();
        const auto r = Crx::verify(crx, QString::fromLatin1(id));
        QVERIFY2(r.ok, qPrintable(r.problem));
        QCOMPARE(Crx::idOfKey(r.key), QString::fromLatin1(id));
        QTemporaryDir dir;
        QCOMPARE(Zip::extract(r.zip, dir.path()), QString());
        QVERIFY(QFile::exists(dir.path() + u"/manifest.json"));
        // the same file with one byte changed, and for another id
        QByteArray bad = crx;
        bad[bad.size() / 2] = char(bad.at(bad.size() / 2) ^ 1);
        QVERIFY(!Crx::verify(bad, QString::fromLatin1(id)).ok);
        QVERIFY(!Crx::verify(crx, QStringLiteral("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")).ok);
    }

    // WEBSTORE_FIXTURES_OUT=<dir>: the files tools/check-engine's webstore group serves in Google's place: a good extension
    // (with a content script) and one whose archive was changed after signing. Their ids go to <dir>/ids.txt.
    void writeFixtures() {
        const QByteArray out = qgetenv("WEBSTORE_FIXTURES_OUT");
        if (out.isEmpty())
            QSKIP("WEBSTORE_FIXTURES_OUT not set");
        const QString dir = QString::fromLocal8Bit(out);
        QDir().mkpath(dir);
        const auto write = [&](const QString &name, const QByteArray &data) {
            QFile f(dir + u'/' + name);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(data);
        };
        const Key good = rsa(), bad = rsa();
        const QByteArray manifest = J("{'manifest_version':3,'name':'Check extension','version':'1.0','permissions':['declarativeNetRequest','history'],"
                                      "'host_permissions':['<all_urls>'],'content_scripts':[{'matches':['http://*/*'],'js':['cs.js']}]}");
        // the unpacked copy carries the key, as WebStore writes it, so the engine gives it the id of the store's extension
        QJsonObject withKey = QJsonDocument::fromJson(manifest).object();
        withKey.insert(u"key"_s, QString::fromLatin1(good.der().toBase64()));
        const QByteArray zip = makeZip({{u"manifest.json"_s, manifest},
                                        {u"cs.js"_s, "document.documentElement.setAttribute('data-thyris-ext', chrome.runtime.id);"}});
        // the same extension unpacked, for --load-extension (WEBSTORE_LOAD): the engine runs it as it would once added
        QDir().mkpath(dir + u"/ext");
        write(u"ext/manifest.json"_s, QJsonDocument(withKey).toJson());
        write(u"ext/cs.js"_s, "document.documentElement.setAttribute('data-thyris-ext', chrome.runtime.id);");
        write(idOf(good) + u".crx", buildCrx(zip, good, {good}));
        QByteArray tampered = buildCrx(zip, bad, {bad});
        tampered[tampered.size() - 60] = char(tampered.at(tampered.size() - 60) ^ 2);
        write(idOf(bad) + u".crx", tampered);
        write(u"ids.txt"_s, (idOf(good) + u"," + idOf(bad)).toUtf8());
    }

    // ---- zip
    void zipUnpacks() {
        QTemporaryDir dir;
        QCOMPARE(Zip::extract(goodZip(), dir.path()), QString());
        QFile m(dir.path() + u"/manifest.json");
        QVERIFY(m.open(QIODevice::ReadOnly));
        QVERIFY(m.readAll().contains("manifest_version"));
        QCOMPARE(QFileInfo(dir.path() + u"/icons/16.png").size(), 300);
        QCOMPARE(QFileInfo(dir.path() + u"/js/background.js").size(), 16 * 200);
    }
    void zipRefusals_data() {
        QTest::addColumn<QByteArray>("zip");
        const QByteArray ok = J("{'manifest_version':3}");
        QTest::newRow("dotdot") << makeZip({{QStringLiteral("../evil.js"), "x"}});
        QTest::newRow("dotdot inside") << makeZip({{QStringLiteral("a/../../evil.js"), "x"}});
        QTest::newRow("absolute") << makeZip({{QStringLiteral("/etc/evil.js"), "x"}});
        QTest::newRow("backslash") << makeZip({{QStringLiteral("..\\evil.js"), "x"}});
        QTest::newRow("drive") << makeZip({{QStringLiteral("C:/evil.js"), "x"}});
        QTest::newRow("dotdot dir") << makeZip({{QStringLiteral("../"), {}, false, 040755}});
        QTest::newRow("symlink") << makeZip({{QStringLiteral("manifest.json"), ok}, {QStringLiteral("link"), "/etc/passwd", false, 0120777}});
        QTest::newRow("device") << makeZip({{QStringLiteral("dev"), {}, false, 0020666}});
        QTest::newRow("same name twice") << makeZip({{QStringLiteral("a.js"), "1"}, {QStringLiteral("a.js"), "2"}});
        QTest::newRow("same name other case") << makeZip({{QStringLiteral("a.js"), "1"}, {QStringLiteral("A.js"), "2"}});
        QTest::newRow("encrypted") << makeZip({{QStringLiteral("a.js"), "1", true, 0100644, 1}});
        QTest::newRow("wrong crc") << makeZip({[] { ZipEntry e{QStringLiteral("a.js"), "hello"}; e.overrideCrc = true; e.crcOverride = 1; return e; }()});
        QTest::newRow("size lies low") << makeZip({[] { ZipEntry e{QStringLiteral("a.js"), QByteArray(1 << 20, '\0')}; e.declaredSize = 10; return e; }()});
        QTest::newRow("size lies high") << makeZip({[] { ZipEntry e{QStringLiteral("a.js"), "hello"}; e.declaredSize = 500; return e; }()});
        QTest::newRow("file then folder") << makeZip({{QStringLiteral("a"), "1", false}, {QStringLiteral("a/b.js"), "2", false}});
        QTest::newRow("not a zip") << QByteArray("this is not a zip file at all, just text");
        QTest::newRow("empty") << QByteArray();
        QTest::newRow("truncated") << goodZip().left(100);
    }
    void zipRefusals() {
        QFETCH(QByteArray, zip);
        QTemporaryDir outer;
        QDir().mkpath(outer.path() + u"/in");
        const QString dir = outer.path() + u"/in";
        QVERIFY(!Zip::extract(zip, dir).isEmpty());
        // nothing outside the folder
        QVERIFY(!QFile::exists(outer.path() + u"/evil.js"));
        QVERIFY(!QFile::exists(outer.path() + u"/in/../evil.js"));
        QVERIFY(!QFile::exists(u"/etc/evil.js"_s));
    }
    void zipTooBig() {
        QTemporaryDir dir;
        Zip::Limits small;
        small.fileBytes = 100;
        QVERIFY(!Zip::extract(makeZip({{QStringLiteral("a.js"), QByteArray(1000, 'a')}}), dir.path(), small).isEmpty());
        Zip::Limits few;
        few.files = 2;
        QVERIFY(!Zip::extract(goodZip(), dir.path(), few).isEmpty());
    }
    void zipRefusalWritesNothingBeforeTheBadName() {
        QTemporaryDir dir;
        QVERIFY(!Zip::extract(makeZip({{QStringLiteral("good.js"), "1"}, {QStringLiteral("../bad.js"), "2"}}), dir.path()).isEmpty());
        QVERIFY(QDir(dir.path()).isEmpty());
    }


    // ---- downloads, with a stand-in for the network
    void fetchFollowsGoogleRedirects() {
        QStringList seen;
        const auto transport = scripted({{u"https://clients2.google.com/service/update2/crx?x=1"_s, redirect(u"https://clients2.googleusercontent.com/crx/blobs/a.crx"_s)},
                                         {u"https://clients2.googleusercontent.com/crx/blobs/a.crx"_s, body(QByteArray("FILE"))}}, &seen);
        QByteArray got;
        QString problem = u"unset"_s;
        StoreFetch::get(transport, QUrl(u"https://clients2.google.com/service/update2/crx?x=1"_s), 1000,
                        [&](const QByteArray &b, const QString &p) { got = b; problem = p; });
        QCOMPARE(problem, QString());
        QCOMPARE(got, QByteArray("FILE"));
        QCOMPARE(seen.size(), 2);
    }
    void fetchRefusesRedirectsOutOfGoogle_data() {
        QTest::addColumn<QString>("to");
        QTest::newRow("other host") << u"https://evil.example/x.crx"_s;
        QTest::newRow("http") << u"http://clients2.googleusercontent.com/x.crx"_s;
        QTest::newRow("userinfo") << u"https://clients2.google.com@evil.example/x.crx"_s;
        QTest::newRow("lookalike") << u"https://google.com.evil.example/x.crx"_s;
        QTest::newRow("file") << u"file:///etc/passwd"_s;
        QTest::newRow("port") << u"https://clients2.google.com:4443/x.crx"_s;
    }
    void fetchRefusesRedirectsOutOfGoogle() {
        QFETCH(QString, to);
        QStringList seen;
        const auto transport = scripted({{u"https://clients2.google.com/service/update2/crx?x=1"_s, redirect(to)}}, &seen);
        QString problem;
        StoreFetch::get(transport, QUrl(u"https://clients2.google.com/service/update2/crx?x=1"_s), 1000, [&](const QByteArray &, const QString &p) { problem = p; });
        QVERIFY(problem.contains(u"doesn't trust"));
        QCOMPARE(seen.size(), 1);               // the other address was never asked
    }
    void fetchRefusesOtherStartAndLoops() {
        QStringList seen;
        QString problem;
        StoreFetch::get(scripted({}, &seen), QUrl(u"https://evil.example/x"_s), 1000, [&](const QByteArray &, const QString &p) { problem = p; });
        QVERIFY(!problem.isEmpty());
        QVERIFY(seen.isEmpty());
        // a ring of redirects
        QHash<QString, StoreFetch::Reply> ring;
        for (int i = 0; i < 10; ++i)
            ring.insert(u"https://clients2.google.com/r%1"_s.arg(i), redirect(u"https://clients2.google.com/r%1"_s.arg(i + 1)));
        problem.clear();
        StoreFetch::get(scripted(ring, &seen), QUrl(u"https://clients2.google.com/r0"_s), 1000, [&](const QByteArray &, const QString &p) { problem = p; });
        QVERIFY(problem.contains(u"circles"));
        QCOMPARE(seen.size(), StoreFetch::maxRedirects + 1);
    }
    void fetchSaysWhatWentWrong() {
        const auto run = [&](StoreFetch::Reply r) {
            QString problem;
            StoreFetch::get(scripted({{u"https://clients2.google.com/a"_s, r}}, nullptr), QUrl(u"https://clients2.google.com/a"_s), 1000,
                            [&](const QByteArray &, const QString &p) { problem = p; });
            return problem;
        };
        StoreFetch::Reply r;
        r.status = 404;
        QVERIFY(run(r).contains(u"no extension"));
        r.status = 500;
        QVERIFY(run(r).contains(u"500"));
        StoreFetch::Reply down;
        down.failed = true;
        QVERIFY(run(down).contains(u"connection"));
        StoreFetch::Reply big;
        big.tooBig = true;
        big.status = 200;
        QVERIFY(run(big).contains(u"too big"));
    }
    void realUpdateAnswer() {
        QFile f(QStringLiteral(SRCDIR "/update-answer.xml"));
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QByteArray xml = f.readAll();
        const QString id = u"ddkjiahejlhfcafbddmgiahcphecmpfh"_s;
        auto a = StoreRules::parseUpdateCheck(xml, id, u"2025.1.1"_s);
        QVERIFY(a.ok && a.newer);
        QCOMPARE(a.version, u"2026.1026.1812"_s);
        QCOMPARE(a.sha256, u"6763ff30cb7b89bf3b411908c03674b5d4e98c12a38fbae776fd057d1a8d1837"_s);
        QVERIFY(a.file.host().endsWith(u"googleusercontent.com"));
        a = StoreRules::parseUpdateCheck(xml, id, u"2026.1026.1812"_s);
        QVERIFY(a.ok && !a.newer);
    }

    // ---- the store's rules
    void itemPages_data() {
        QTest::addColumn<QString>("url");
        QTest::addColumn<QString>("id");
        const QString id = QStringLiteral("ddkjiahejlhfcafbddmgiahcphecmpfh");
        QTest::newRow("new store") << "https://chromewebstore.google.com/detail/ublock-origin-lite/" + id << id;
        QTest::newRow("query and fragment") << "https://chromewebstore.google.com/detail/x/" + id + "?hl=en&utm=1#top" << id;
        QTest::newRow("trailing slash") << "https://chromewebstore.google.com/detail/x/" + id + "/" << id;
        QTest::newRow("old store") << "https://chrome.google.com/webstore/detail/x/" + id << id;
        QTest::newRow("encoded name") << "https://chromewebstore.google.com/detail/%D8%B9%D8%B1%D8%A8%D9%8A/" + id << id;
        QTest::newRow("explicit port 443") << "https://chromewebstore.google.com:443/detail/x/" + id << id;
        QTest::newRow("http") << "http://chromewebstore.google.com/detail/x/" + id << QString();
        QTest::newRow("other port") << "https://chromewebstore.google.com:8443/detail/x/" + id << QString();
        QTest::newRow("userinfo") << "https://chromewebstore.google.com@evil.example/detail/x/" + id << QString();
        QTest::newRow("userinfo2") << "https://user:pw@chromewebstore.google.com/detail/x/" + id << QString();
        QTest::newRow("lookalike host") << "https://chromewebstore.google.com.evil.example/detail/x/" + id << QString();
        QTest::newRow("lookalike prefix") << "https://evilchromewebstore.google.com/detail/x/" + id << QString();
        QTest::newRow("other google host") << "https://www.google.com/detail/x/" + id << QString();
        QTest::newRow("old store on new host") << "https://chromewebstore.google.com/webstore/detail/x/" + id << QString();
        QTest::newRow("new path on old host") << "https://chrome.google.com/detail/x/" + id << QString();
        QTest::newRow("short id") << "https://chromewebstore.google.com/detail/x/" + id.left(31) << QString();
        QTest::newRow("long id") << "https://chromewebstore.google.com/detail/x/" + id + "a" << QString();
        QTest::newRow("id with q") << "https://chromewebstore.google.com/detail/x/" + id.left(31) + "q" << QString();
        QTest::newRow("uppercase id") << "https://chromewebstore.google.com/detail/x/" + id.toUpper() << QString();
        QTest::newRow("subpage") << "https://chromewebstore.google.com/detail/x/" + id + "/reviews" << QString();
        QTest::newRow("no name") << "https://chromewebstore.google.com/detail/" + id << QString();
        QTest::newRow("search page") << "https://chromewebstore.google.com/search/ublock" << QString();
        QTest::newRow("id in query only") << "https://chromewebstore.google.com/?q=/detail/x/" + id << QString();
        QTest::newRow("id in fragment only") << "https://chromewebstore.google.com/#/detail/x/" + id << QString();
        QTest::newRow("dotdot") << "https://chromewebstore.google.com/detail/../" + id << QString();
        QTest::newRow("other site naming the path") << "https://example.com/detail/x/" + id << QString();
        QTest::newRow("file") << "file:///detail/x/" + id << QString();
        QTest::newRow("empty") << QString() << QString();
    }
    void itemPages() {
        QFETCH(QString, url);
        QFETCH(QString, id);
        QCOMPARE(StoreRules::itemId(QUrl(url)), id);
    }
    void googleAddresses_data() {
        QTest::addColumn<QString>("url");
        QTest::addColumn<bool>("allowed");
        QTest::newRow("update service") << "https://clients2.google.com/service/update2/crx?x=1" << true;
        QTest::newRow("blobs") << "https://clients2.googleusercontent.com/crx/blobs/abc/x.crx" << true;
        QTest::newRow("gvt1") << "https://edgedl.me.gvt1.com/edgedl/x.crx" << true;
        QTest::newRow("deep google host") << "https://a.b.c.google.com/x" << false;
        QTest::newRow("sites") << "https://sites.google.com/x/y.crx" << false;
        QTest::newRow("docs") << "https://docs.google.com/x" << false;
        QTest::newRow("drive") << "https://drive.google.com/x" << false;
        QTest::newRow("user content") << "https://lh3.googleusercontent.com/x" << false;
        QTest::newRow("other clients") << "https://clients1.google.com/x" << false;
        QTest::newRow("uppercase host") << "https://CLIENTS2.GOOGLE.COM/x" << true;
        QTest::newRow("http") << "http://clients2.google.com/x" << false;
        QTest::newRow("bare google.com") << "https://google.com/x" << false;
        QTest::newRow("bare gvt1") << "https://gvt1.com/x" << false;
        QTest::newRow("suffix lookalike") << "https://evilgoogle.com/x" << false;
        QTest::newRow("suffix lookalike 2") << "https://clients2.notgoogle.com/x" << false;
        QTest::newRow("prefix lookalike") << "https://clients2.google.com.evil.example/x" << false;
        QTest::newRow("userinfo trick") << "https://clients2.google.com@evil.example/x" << false;
        QTest::newRow("userinfo on google") << "https://user@clients2.google.com/x" << false;
        QTest::newRow("other port") << "https://clients2.google.com:8080/x" << false;
        QTest::newRow("port 443") << "https://clients2.google.com:443/x" << true;
        QTest::newRow("ip") << "https://142.250.1.1/x" << false;
        QTest::newRow("localhost") << "https://localhost/x" << false;
        QTest::newRow("googleusercontent lookalike") << "https://googleusercontent.com.evil.example/x" << false;
        QTest::newRow("data") << "data:text/plain,hi" << false;
        QTest::newRow("file") << "file:///etc/passwd" << false;
        QTest::newRow("ftp") << "ftp://clients2.google.com/x" << false;
        QTest::newRow("backslash trick") << "https://evil.example\\@clients2.google.com/x" << false;
    }
    void googleAddresses() {
        QFETCH(QString, url);
        QFETCH(bool, allowed);
        QCOMPARE(StoreRules::googleAddress(QUrl(url)), allowed);
    }
    void redirects() {
        const QUrl from(u"https://clients2.google.com/service/update2/crx?x=1"_s);
        QCOMPARE(StoreRules::nextHop(from, u"https://clients2.googleusercontent.com/crx/blobs/a/b.crx"_s).host(), u"clients2.googleusercontent.com"_s);
        QCOMPARE(StoreRules::nextHop(from, u"/other/path"_s).toString(), u"https://clients2.google.com/other/path"_s);
        QVERIFY(StoreRules::nextHop(from, u"https://evil.example/x.crx"_s).isEmpty());
        QVERIFY(StoreRules::nextHop(from, u"http://clients2.google.com/x.crx"_s).isEmpty());          // downgrade
        QVERIFY(StoreRules::nextHop(from, u"//evil.example/x.crx"_s).isEmpty());                      // protocol-relative
        QVERIFY(StoreRules::nextHop(from, u"https://clients2.google.com@evil.example/x"_s).isEmpty());
        QVERIFY(StoreRules::nextHop(from, u"file:///etc/passwd"_s).isEmpty());
        QVERIFY(StoreRules::nextHop(from, QString()).isEmpty());
    }
    void urls() {
        const QString id = QStringLiteral("ddkjiahejlhfcafbddmgiahcphecmpfh");
        const QUrl u = StoreRules::fileUrl(id, u"154.0.8037.98"_s);
        QCOMPARE(u.toEncoded(), QByteArray("https://clients2.google.com/service/update2/crx?response=redirect&prodversion=154.0.8037.98"
                                           "&acceptformat=crx3&x=id%3Dddkjiahejlhfcafbddmgiahcphecmpfh%26installsource%3Dondemand%26uc"));
        QVERIFY(StoreRules::googleAddress(u));
        const QUrl c = StoreRules::updateCheckUrl(id, u"154.0.8037.98"_s, u"2025.1.2"_s);
        QCOMPARE(c.toEncoded(), QByteArray("https://clients2.google.com/service/update2/crx?prodversion=154.0.8037.98&acceptformat=crx3"
                                           "&x=id%3Dddkjiahejlhfcafbddmgiahcphecmpfh%26v%3D2025.1.2%26uc"));
        // nothing but a plain id and version goes into an address
        QVERIFY(StoreRules::fileUrl(u"x&y=1"_s, u"154.0.0.0"_s).isEmpty());
        QVERIFY(StoreRules::fileUrl(id, u"154&evil=1"_s).isEmpty());
        QVERIFY(StoreRules::updateCheckUrl(id, u"154.0.0.0"_s, u"1&evil=1"_s).isEmpty());
        QVERIFY(StoreRules::updateCheckUrl(id, u"154.0.0.0"_s, u"1.0\n"_s).isEmpty());
    }
    void updateAnswers() {
        const QString id = QStringLiteral("ddkjiahejlhfcafbddmgiahcphecmpfh");
        const auto xml = [&](const QString &check) {
            return QStringLiteral("<?xml version='1.0' encoding='UTF-8'?><gupdate xmlns=\"http://www.google.com/update2/response\" protocol=\"2.0\">"
                                  "<app appid=\"%1\" status=\"ok\">%2</app></gupdate>").arg(id, check).toUtf8();
        };
        auto a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"https://clients2.googleusercontent.com/crx/blobs/x.crx\" "
                                                  "hash_sha256=\"ABCD\" status=\"ok\" version=\"2025.2.0\"/>"_s), id, u"2025.1.2"_s);
        QVERIFY(a.ok && a.newer);
        QCOMPARE(a.version, u"2025.2.0"_s);
        QCOMPARE(a.sha256, u"abcd"_s);
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"https://clients2.googleusercontent.com/crx/blobs/x.crx\" status=\"ok\" version=\"2025.1.2\"/>"_s), id, u"2025.1.2"_s);
        QVERIFY(a.ok && !a.newer);
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck status=\"noupdate\"/>"_s), id, u"1.0"_s);
        QVERIFY(a.ok && !a.newer);
        // a file from outside Google is not an answer
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"https://evil.example/x.crx\" status=\"ok\" version=\"9.0\"/>"_s), id, u"1.0"_s);
        QVERIFY(!a.ok);
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"http://clients2.google.com/x.crx\" status=\"ok\" version=\"9.0\"/>"_s), id, u"1.0"_s);
        QVERIFY(!a.ok);
        // an answer about another extension, or not xml
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"https://clients2.google.com/x.crx\" status=\"ok\" version=\"9.0\"/>"_s), u"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"_s, u"1.0"_s);
        QVERIFY(!a.ok);
        QVERIFY(!StoreRules::parseUpdateCheck("<html>not xml", id, u"1.0"_s).ok);
        QVERIFY(!StoreRules::parseUpdateCheck(xml(u"<updatecheck status=\"error-unknownApplication\"/>"_s), id, u"1.0"_s).ok);
        a = StoreRules::parseUpdateCheck(xml(u"<updatecheck codebase=\"https://clients2.google.com/x.crx\" status=\"ok\" version=\"9.0; rm -rf\"/>"_s), id, u"1.0"_s);
        QVERIFY(!a.ok);
    }
    void versions() {
        QVERIFY(StoreRules::versionNewer(u"1.10"_s, u"1.9"_s));
        QVERIFY(StoreRules::versionNewer(u"2025.1.2.1"_s, u"2025.1.2"_s));
        QVERIFY(!StoreRules::versionNewer(u"1.0"_s, u"1.0.0"_s));
        QVERIFY(!StoreRules::versionNewer(u"1.2"_s, u"1.3"_s));
    }
    void permissionWordsOf() {
        const auto m = [](const QByteArray &json) { return QJsonDocument::fromJson(json).object(); };
        // uBlock Origin Lite's kind: block things, on every site
        auto w = StoreRules::permissionWords(m(J("{'permissions':['declarativeNetRequest','scripting','storage','activeTab'],'host_permissions':['<all_urls>']}")));
        QCOMPARE(w.value(0), u"Read and change the pages you visit, on every site"_s);
        QVERIFY(w.contains(u"Block things on pages"_s));
        QVERIFY(w.contains(u"Use the page you are on when you press its button"_s));
        QCOMPARE(w.size(), 3);                  // scripting and storage say nothing
        w = StoreRules::permissionWords(m(J("{'permissions':['history','tabs'],'content_scripts':[{'matches':['https://*.example.com/*','https://other.org/x']}]}")));
        QCOMPARE(w.value(0), u"Read and change your data on example.com and other.org"_s);
        QVERIFY(w.contains(u"See your browsing history"_s));
        w = StoreRules::permissionWords(m(J("{'host_permissions':['https://a.com/*','https://b.com/*','https://c.com/*','https://d.com/*']}")));
        QCOMPARE(w.value(0), u"Read and change your data on a.com, b.com and 2 other sites"_s);
        w = StoreRules::permissionWords(m(J("{'host_permissions':['https://a.com/*','https://b.com/*','https://c.com/*']}")));
        QCOMPARE(w.value(0), u"Read and change your data on a.com, b.com and 1 other site"_s);
        QVERIFY(StoreRules::permissionWords(m(J("{'permissions':['storage','alarms']}"))).isEmpty());
        QVERIFY(StoreRules::permissionWords(m(J("{'permissions':[1,null,{'a':1}],'host_permissions':'nope'}"))).isEmpty());
        QVERIFY(StoreRules::permissionWords(m(J("{'host_permissions':['*://*/*']}"))).value(0).contains(u"every site"));
        QVERIFY(StoreRules::permissionWords(m(J("{'host_permissions':['http://*/*']}"))).value(0).contains(u"every site"));
        // the far-reaching first
        w = StoreRules::permissionWords(m(J("{'permissions':['notifications','cookies','history']}")));
        QCOMPARE(w.value(0), u"See your browsing history"_s);
        QCOMPARE(w.value(2), u"Show notifications"_s);
    }
    // the attacks the security review tried: an update that widens its reach must be seen as asking for more
    void updateWidenings_data() {
        QTest::addColumn<QByteArray>("before");
        QTest::addColumn<QByteArray>("now");
        const QByteArray a = "{'host_permissions':['https://example.com/*']}";
        QTest::newRow("subdomains") << a << QByteArray("{'host_permissions':['https://*.example.com/*']}");
        QTest::newRow("http") << a << QByteArray("{'host_permissions':['http://example.com/*']}");
        QTest::newRow("ws") << a << QByteArray("{'host_permissions':['ws://example.com/*']}");
        QTest::newRow("any scheme") << a << QByteArray("{'host_permissions':['*://example.com/*']}");
        QTest::newRow("wider path") << QByteArray("{'host_permissions':['https://example.com/a']}") << QByteArray("{'host_permissions':['https://example.com/*']}");
        QTest::newRow("sidePanel") << a << QByteArray("{'host_permissions':['https://example.com/*'],'permissions':['sidePanel']}");
        QTest::newRow("offscreen") << a << QByteArray("{'host_permissions':['https://example.com/*'],'permissions':['offscreen']}");
        QTest::newRow("declarativeContent") << a << QByteArray("{'host_permissions':['https://example.com/*'],'permissions':['declarativeContent']}");
        QTest::newRow("invented permission") << a << QByteArray("{'host_permissions':['https://example.com/*'],'permissions':['somethingNew']}");
        QTest::newRow("optional permission") << a << QByteArray("{'host_permissions':['https://example.com/*'],'optional_permissions':['history']}");
        QTest::newRow("optional hosts") << a << QByteArray("{'host_permissions':['https://example.com/*'],'optional_host_permissions':['<all_urls>']}");
        QTest::newRow("externally_connectable") << a << QByteArray("{'host_permissions':['https://example.com/*'],'externally_connectable':{'matches':['*://*/*']}}");
        QTest::newRow("externally_connectable ids") << a << QByteArray("{'host_permissions':['https://example.com/*'],'externally_connectable':{'ids':['*']}}");
        QTest::newRow("web_accessible") << a << QByteArray("{'host_permissions':['https://example.com/*'],'web_accessible_resources':[{'resources':['a.js'],'matches':['<all_urls>']}]}");
        QTest::newRow("all_urls from https star") << QByteArray("{'host_permissions':['https://*/*']}") << QByteArray("{'host_permissions':['<all_urls>']}");
        QTest::newRow("file") << a << QByteArray("{'host_permissions':['https://example.com/*','file:///*']}");
    }
    void updateWidenings() {
        QFETCH(QByteArray, before);
        QFETCH(QByteArray, now);
        const auto m = [](const QByteArray &json) { return QJsonDocument::fromJson(json).object(); };
        QVERIFY2(!StoreRules::addedWords(m(J(before.constData())), m(J(now.constData()))).isEmpty(), "an update that asks for more must be asked about");
    }
    void updateNarrowingsAreQuiet() {
        const auto m = [](const QByteArray &json) { return QJsonDocument::fromJson(json).object(); };
        QVERIFY(StoreRules::addedWords(m(J("{'host_permissions':['https://*.example.com/*']}")), m(J("{'host_permissions':['https://a.example.com/x','https://example.com/*']}"))).isEmpty());
        QVERIFY(StoreRules::addedWords(m(J("{'host_permissions':['*://example.com/*']}")), m(J("{'host_permissions':['https://example.com/*']}"))).isEmpty());
        QVERIFY(StoreRules::addedWords(m(J("{'host_permissions':['<all_urls>']}")), m(J("{'host_permissions':['*://*/*'],'permissions':['storage']}"))).isEmpty());
    }
    void unlistedPermissionsAreShown() {
        const auto m = [](const QByteArray &json) { return QJsonDocument::fromJson(json).object(); };
        QVERIFY(!StoreRules::permissionWords(m(J("{'permissions':['sidePanel']}"))).isEmpty());
        QVERIFY(!StoreRules::permissionWords(m(J("{'optional_host_permissions':['<all_urls>']}"))).isEmpty());
        QVERIFY(StoreRules::permissionWords(m(J("{'permissions':['storage']}"))).isEmpty());
    }
    void updateAsksOnlyForMore() {
        const auto m = [](const QByteArray &json) { return QJsonDocument::fromJson(json).object(); };
        const auto old = m(J("{'permissions':['declarativeNetRequest'],'host_permissions':['https://a.com/*']}"));
        QVERIFY(StoreRules::addedWords(old, old).isEmpty());
        // fewer, or only harmless ones more: nothing to ask
        QVERIFY(StoreRules::addedWords(old, m(J("{'permissions':['declarativeNetRequest','storage'],'host_permissions':['https://a.com/*']}"))).isEmpty());
        QVERIFY(StoreRules::addedWords(old, m(J("{}"))).isEmpty());
        // another site, every site, history
        QCOMPARE(StoreRules::addedWords(old, m(J("{'permissions':['declarativeNetRequest'],'host_permissions':['https://a.com/*','https://b.com/*']}"))),
                 QStringList{u"Read and change your data on b.com"_s});
        QCOMPARE(StoreRules::addedWords(old, m(J("{'permissions':['declarativeNetRequest'],'host_permissions':['<all_urls>']}"))),
                 QStringList{u"Read and change the pages you visit, on every site"_s});
        QCOMPARE(StoreRules::addedWords(old, m(J("{'permissions':['declarativeNetRequest','history'],'host_permissions':['https://a.com/*']}"))),
                 QStringList{u"See your browsing history"_s});
        // already on every site: a named site is nothing new
        QVERIFY(StoreRules::addedWords(m(J("{'host_permissions':['<all_urls>']}")), m(J("{'host_permissions':['https://b.com/*']}"))).isEmpty());
        // a content script's match counts as a site
        QVERIFY(!StoreRules::addedWords(old, m(J("{'permissions':['declarativeNetRequest'],'host_permissions':['https://a.com/*'],'content_scripts':[{'matches':['https://c.com/*']}]}"))).isEmpty());
    }

    // ---- the whole flow on a scratch store, with a stand-in for Google
private:
    struct Rig {
        QTemporaryDir store, google;
        Key key = rsa();
        QString id = idOf(key);
        WebStore web;
        Rig() {
            Extensions::storeOverride = store.path() + u"/added";
            WebStore::useFixtures(google.path());
            WebStore::requested.clear();
            WebStore::dryRun = true;
        }
        ~Rig() {
            Extensions::storeOverride.clear();
            WebStore::transportOverride = nullptr;
        }
        static QByteArray extZip(const QString &version, const QByteArray &permissions = "[\"declarativeNetRequest\"]", const QByteArray &hosts = "[\"<all_urls>\"]") {
            const QByteArray manifest = "{\"manifest_version\":3,\"name\":\"Test ext\",\"version\":\"" + version.toUtf8() + "\",\"permissions\":" + permissions
                                        + ",\"host_permissions\":" + hosts + ",\"icons\":{\"16\":\"i.png\"}}";
            return makeZip({{QStringLiteral("manifest.json"), manifest}, {QStringLiteral("i.png"), QByteArray("\x89PNG\r\n\x1a\n") + QByteArray(40, 'p')},
                            {QStringLiteral("sw.js"), "// worker"}});
        }
        void serve(const QByteArray &crx, const QString &name = QString()) {
            QFile f(google.path() + u'/' + (name.isEmpty() ? id : name) + u".crx");
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(crx);
        }
        void answer(const QString &version, const QString &file) {
            QFile f(google.path() + u'/' + id + u".xml");
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(("<?xml version='1.0'?><gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'><app appid='" + id + "' status='ok'>"
                     "<updatecheck codebase='https://clients2.googleusercontent.com/crx/blobs/fixture/" + file + "' status='ok' version='" + version + "'/></app></gupdate>").toUtf8());
        }
        bool leftovers() const {
            for (const QString &n : QDir(Extensions::store()).entryList(QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot))
                if (n.startsWith(u".staged-") || n.startsWith(u".incoming-"))
                    return true;
            return false;
        }
    };
    // `run` listens after the job started; the stand-in answers on a later turn of the loop, so this holds
    QVariantMap fromStore(Rig &rig, QString *problem) {
        QSignalSpy ok(&rig.web, &WebStore::prepared), no(&rig.web, &WebStore::refused);
        const int ticket = rig.web.fromStore(rig.id);
        for (int i = 0; i < 100 && ok.isEmpty() && no.isEmpty(); ++i)
            QTest::qWait(20);
        Q_UNUSED(ticket);
        if (!ok.isEmpty())
            return ok.first().at(1).toMap();
        *problem = no.isEmpty() ? u"no answer"_s : no.first().at(1).toString();
        return {};
    }

private slots:
    void flowAddsFromTheStore() {
        Rig rig;
        rig.serve(buildCrx(Rig::extZip(u"1.0"_s), rig.key, {rig.key}));
        QString problem;
        const QVariantMap info = fromStore(rig, &problem);
        QVERIFY2(!info.isEmpty(), qPrintable(problem));
        QCOMPARE(info.value(u"name"_s).toString(), u"Test ext"_s);
        QCOMPARE(info.value(u"version"_s).toString(), u"1.0"_s);
        QVERIFY(info.value(u"icon"_s).toString().startsWith(u"data:image/png;base64,"));
        QCOMPARE(info.value(u"words"_s).toStringList().value(0), u"Read and change the pages you visit, on every site"_s);
        // asked of Google's two hosts only, in the order the service works
        QCOMPARE(WebStore::requested.size(), 2);
        QVERIFY(WebStore::requested.at(0).startsWith(u"https://clients2.google.com/service/update2/crx?response=redirect&prodversion=154.0.0.0&acceptformat=crx3&x=id%3D"));
        QVERIFY(WebStore::requested.at(1).startsWith(u"https://clients2.googleusercontent.com/"));
        // nothing is in the list until the person says yes
        QVERIFY(Extensions::read().isEmpty());
        const QVariantMap added = rig.web.add(info.value(u"ticket"_s).toInt());
        QVERIFY2(added.value(u"ok"_s).toBool(), qPrintable(added.value(u"problem"_s).toString()));
        const QJsonObject e = Extensions::read().at(0).toObject();
        QCOMPARE(e.value(u"id"_s).toString(), rig.id);
        QCOMPARE(e.value(u"source"_s).toString(), u"store"_s);
        QCOMPARE(e.value(u"version"_s).toString(), u"1.0"_s);
        QVERIFY(e.value(u"added"_s).toDouble() > 0);
        // the folder holds the extension, with the store's key in its manifest: the engine gives it the store's id
        const QJsonObject m = Extensions::manifestOf(Extensions::store() + u'/' + rig.id);
        QCOMPARE(Crx::idOfKey(QByteArray::fromBase64(m.value(u"key"_s).toString().toLatin1())), rig.id);
        QCOMPARE(Extensions::loadPaths(), QStringList{Extensions::store() + u'/' + rig.id});
        QVERIFY(!rig.leftovers());
        // a second Add of the same extension is not asked
        QString again;
        QVERIFY(fromStore(rig, &again).isEmpty());
        QVERIFY(again.contains(u"already added"));
        // Remove deletes its files
        Extensions ext;
        ext.uninstallExtension(QVariantMap{{u"id"_s, rig.id}});
        QVERIFY(!QFileInfo::exists(Extensions::store() + u'/' + rig.id));
        QVERIFY(Extensions::read().isEmpty());
    }
    void fileKeyIsStripped() {
        Rig rig;
        QTemporaryDir src;
        QDir(src.path()).mkpath(u"ext"_s);
        QFile f(src.path() + u"/ext/manifest.json"_s);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(J("{'manifest_version':3,'name':'Sideloaded','version':'1.0','key':\"") + rig.key.der().toBase64() + "\"}");
        f.close();
        QString problem;
        QVariantMap info;
        QVERIFY2(Extensions::commit(src.path() + u"/ext"_s, false, Extensions::Added(), &problem, &info), qPrintable(problem));
        const QString to = Extensions::store() + u'/' + info.value(u"id"_s).toString();
        QVERIFY(!Extensions::manifestOf(to).contains(u"key"_s));
        QVERIFY(Extensions::manifestOf(src.path() + u"/ext"_s).contains(u"key"_s));      // the person's own folder is left alone
    }
    void flowRefusesTamperedAndWrongFiles() {
        Rig rig;
        const QByteArray good = buildCrx(Rig::extZip(u"1.0"_s), rig.key, {rig.key});
        QString problem;
        // a changed byte in the archive
        QByteArray bad = good;
        bad[bad.size() - 40] = char(bad.at(bad.size() - 40) ^ 4);
        rig.serve(bad);
        QVERIFY(fromStore(rig, &problem).isEmpty());
        QVERIFY2(problem.contains(u"check out") || problem.contains(u"damaged"), qPrintable(problem));
        // another extension's file served for this id
        const Key other = rsa();
        rig.serve(buildCrx(Rig::extZip(u"1.0"_s), other, {other}));
        problem.clear();
        QVERIFY(fromStore(rig, &problem).isEmpty());
        QVERIFY2(problem.contains(u"different extension"), qPrintable(problem));
        // a zip entry that climbs out of its folder, validly signed
        rig.serve(buildCrx(makeZip({{u"manifest.json"_s, "{}"}, {u"../../escape.js"_s, "x"}}), rig.key, {rig.key}));
        problem.clear();
        QVERIFY(fromStore(rig, &problem).isEmpty());
        QVERIFY2(problem.contains(u"outside its own folder"), qPrintable(problem));
        QVERIFY(!QFileInfo::exists(rig.store.path() + u"/escape.js"));
        // a symlink, validly signed
        rig.serve(buildCrx(makeZip({{u"manifest.json"_s, "{}"}, {u"link"_s, "/etc/passwd", false, 0120777}}), rig.key, {rig.key}));
        problem.clear();
        QVERIFY(fromStore(rig, &problem).isEmpty());
        QVERIFY2(problem.contains(u"link"), qPrintable(problem));
        // Manifest 2, validly signed
        rig.serve(buildCrx(makeZip({{u"manifest.json"_s, "{\"manifest_version\":2,\"name\":\"Old\",\"version\":\"1\"}"}}), rig.key, {rig.key}));
        problem.clear();
        QVERIFY(fromStore(rig, &problem).isEmpty());
        QVERIFY2(problem.contains(u"older version of Chrome"), qPrintable(problem));
        // nothing left: no list, no folder, no scratch
        QVERIFY(Extensions::read().isEmpty());
        QVERIFY(!rig.leftovers());
        QVERIFY(!QFileInfo::exists(Extensions::store() + u'/' + rig.id));
    }
    void flowAFileFromTheZipRoute() {
        Rig rig;
        QTemporaryDir files;
        QFile f(files.path() + u"/slip.zip");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(makeZip({{u"manifest.json"_s, "{}"}, {u"../x.js"_s, "x"}}));
        f.close();
        QSignalSpy no(&rig.web, &WebStore::refused);
        rig.web.fromFile(f.fileName());
        QVERIFY(no.wait(2000));
        QVERIFY(no.first().at(1).toString().contains(u"outside its own folder"));
        QVERIFY(!QFileInfo::exists(files.path() + u"/../x.js"));
        // a good one: folder inside the zip
        QFile g(files.path() + u"/good.zip");
        QVERIFY(g.open(QIODevice::WriteOnly));
        g.write(makeZip({{u"inner/"_s, {}, false, 040755}, {u"inner/manifest.json"_s, "{\"manifest_version\":3,\"name\":\"From file\",\"version\":\"2\"}"}}));
        g.close();
        QSignalSpy ok(&rig.web, &WebStore::prepared);
        rig.web.fromFile(g.fileName());
        QVERIFY(ok.wait(2000));
        const QVariantMap added = rig.web.add(ok.first().at(1).toMap().value(u"ticket"_s).toInt());
        QVERIFY(added.value(u"ok"_s).toBool());
        QCOMPARE(Extensions::read().at(0).toObject().value(u"source"_s).toString(), u"file"_s);
        QVERIFY(!rig.leftovers());
    }
    void flowDiscardLeavesNothing() {
        Rig rig;
        rig.serve(buildCrx(Rig::extZip(u"1.0"_s), rig.key, {rig.key}));
        QString problem;
        const QVariantMap info = fromStore(rig, &problem);
        QVERIFY(rig.leftovers());           // staged, waiting for the answer
        rig.web.discard(info.value(u"ticket"_s).toInt());
        QVERIFY(!rig.leftovers());
        QVERIFY(Extensions::read().isEmpty());
    }
    void flowUpdates() {
        Rig rig;
        rig.serve(buildCrx(Rig::extZip(u"1.0"_s), rig.key, {rig.key}));
        QString problem;
        QVERIFY(rig.web.add(fromStore(rig, &problem).value(u"ticket"_s).toInt()).value(u"ok"_s).toBool());
        const QString live = Extensions::store() + u'/' + rig.id;

        // 1.1 asks for nothing new: kept beside, replaces 1.0 at the next start, no question
        rig.serve(buildCrx(Rig::extZip(u"1.1"_s), rig.key, {rig.key}), u"v11"_s);
        rig.answer(u"1.1"_s, u"v11.crx"_s);
        QSignalSpy checked(&rig.web, &WebStore::checked);
        WebStore::requested.clear();
        rig.web.checkUpdates();
        QVERIFY(!checked.isEmpty() || checked.wait(3000));
        QVERIFY(WebStore::requested.at(0).contains(u"prodversion=154.0.0.0&acceptformat=crx3&x=id%3D" + rig.id + u"%26v%3D1.0%26uc"));
        QCOMPARE(Extensions::manifestOf(live).value(u"version"_s).toString(), u"1.0"_s);   // not yet
        QVERIFY(Extensions::read().at(0).toObject().value(u"pending"_s).toObject().value(u"approved"_s).toBool());
        QVERIFY(rig.web.updateAsks().isEmpty());
        // once a day: another check at once asks Google nothing
        const int asked = WebStore::requested.size();
        rig.web.checkUpdates();
        QTest::qWait(100);
        QCOMPARE(WebStore::requested.size(), asked);
        WebStore::startUp();
        QCOMPARE(Extensions::manifestOf(live).value(u"version"_s).toString(), u"1.1"_s);
        QCOMPARE(Crx::idOfKey(QByteArray::fromBase64(Extensions::manifestOf(live).value(u"key"_s).toString().toLatin1())), rig.id);
        QCOMPARE(Extensions::read().at(0).toObject().value(u"version"_s).toString(), u"1.1"_s);
        QVERIFY(Extensions::read().at(0).toObject().value(u"pending"_s).isUndefined());
        QVERIFY(!QFileInfo::exists(Extensions::store() + u"/.update-" + rig.id));

        // 1.2 asks for history: the old version stays, one question
        rig.serve(buildCrx(Rig::extZip(u"1.2"_s, "[\"declarativeNetRequest\",\"history\"]"), rig.key, {rig.key}), u"v12"_s);
        rig.answer(u"1.2"_s, u"v12.crx"_s);
        QSignalSpy asks(&rig.web, &WebStore::updatesToAsk);
        rig.web.checkUpdates(true);
        QVERIFY(!asks.isEmpty() || asks.wait(3000));
        WebStore::startUp();
        QCOMPARE(Extensions::manifestOf(live).value(u"version"_s).toString(), u"1.1"_s);   // not without an answer
        QVariantList list = rig.web.updateAsks();
        QCOMPARE(list.size(), 1);
        QCOMPARE(list.at(0).toMap().value(u"words"_s).toStringList(), QStringList{u"See your browsing history"_s});
        QVERIFY(rig.web.updateAsks().isEmpty());                                            // once
        // Not now: this version is not asked about again
        rig.web.answerUpdate(rig.id, false);
        QVERIFY(!QFileInfo::exists(Extensions::store() + u"/.update-" + rig.id));
        QSignalSpy again(&rig.web, &WebStore::checked);
        rig.web.checkUpdates(true);
        QVERIFY(!again.isEmpty() || again.wait(3000));
        QVERIFY(Extensions::read().at(0).toObject().value(u"pending"_s).isUndefined());
        // 1.3 asks again; Yes: it comes at the next start
        rig.serve(buildCrx(Rig::extZip(u"1.3"_s, "[\"declarativeNetRequest\",\"history\"]"), rig.key, {rig.key}), u"v13"_s);
        rig.answer(u"1.3"_s, u"v13.crx"_s);
        QSignalSpy third(&rig.web, &WebStore::updatesToAsk);
        rig.web.checkUpdates(true);
        QVERIFY(!third.isEmpty() || third.wait(3000));
        rig.web.answerUpdate(rig.id, true);
        WebStore::startUp();
        QCOMPARE(Extensions::manifestOf(live).value(u"version"_s).toString(), u"1.3"_s);
        QVERIFY(!rig.leftovers());
    }
    void flowUpdateRefusals() {
        Rig rig;
        rig.serve(buildCrx(Rig::extZip(u"1.0"_s), rig.key, {rig.key}));
        QString problem;
        QVERIFY(rig.web.add(fromStore(rig, &problem).value(u"ticket"_s).toInt()).value(u"ok"_s).toBool());
        const auto attempt = [&](const QByteArray &crx) {
            rig.serve(crx, u"bad"_s);
            rig.answer(u"2.0"_s, u"bad.crx"_s);
            QSignalSpy done(&rig.web, &WebStore::checked);
            rig.web.checkUpdates(true);
            QVERIFY(!done.isEmpty() || done.wait(3000));
            QVERIFY(Extensions::read().at(0).toObject().value(u"pending"_s).isUndefined());
            QVERIFY(!QFileInfo::exists(Extensions::store() + u"/.update-" + rig.id));
            QVERIFY(!rig.leftovers());
            WebStore::startUp();
            QCOMPARE(Extensions::manifestOf(Extensions::store() + u'/' + rig.id).value(u"version"_s).toString(), u"1.0"_s);
        };
        // signed by another key (an attacker's own extension named as this one)
        const Key attacker = rsa();
        attempt(buildCrx(Rig::extZip(u"2.0"_s), attacker, {attacker}));
        // the right key's file with a byte changed
        QByteArray bad = buildCrx(Rig::extZip(u"2.0"_s), rig.key, {rig.key});
        bad[bad.size() - 50] = char(bad.at(bad.size() - 50) ^ 8);
        attempt(bad);
        // an older version offered as newer
        attempt(buildCrx(Rig::extZip(u"0.9"_s), rig.key, {rig.key}));
        // a redirect out of Google in the answer is no answer
        QFile f(rig.google.path() + u'/' + rig.id + u".xml");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("<gupdate><app appid='" + rig.id.toUtf8() + "'><updatecheck codebase='https://evil.example/x.crx' status='ok' version='9.0'/></app></gupdate>");
        f.close();
        QSignalSpy done(&rig.web, &WebStore::checked);
        WebStore::requested.clear();
        rig.web.checkUpdates(true);
        QVERIFY(!done.isEmpty() || done.wait(3000));
        QVERIFY(Extensions::read().at(0).toObject().value(u"pending"_s).isUndefined());
        for (const QString &r : std::as_const(WebStore::requested))
            QVERIFY(!r.contains(u"evil"));
    }
};

QTEST_MAIN(StoreTest)
#include "store_test.moc"
