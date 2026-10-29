#include "crx.h"

#include <QDir>
#include <QFile>
#include <QSet>
#include <QtEndian>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <zlib.h>

namespace {

// The protobuf wire format, only as far as CrxFileHeader needs it: varints, length-delimited fields, and skipping the rest
struct Reader {
    const uchar *p;
    const uchar *end;
    bool bad = false;

    Reader(const QByteArray &b) : p(reinterpret_cast<const uchar *>(b.constData())), end(p + b.size()) {}
    bool done() const { return p >= end; }
    quint64 varint() {
        quint64 v = 0;
        for (int shift = 0; shift < 64; shift += 7) {
            if (p >= end) {
                bad = true;
                return 0;
            }
            const uchar b = *p++;
            v |= quint64(b & 0x7f) << shift;
            if (!(b & 0x80))
                return v;
        }
        bad = true;
        return 0;
    }
    // the next field: its number and wire type; `bytes` is set for a length-delimited one, other types are skipped
    bool field(quint32 &number, QByteArray &bytes, bool &delimited) {
        delimited = false;
        const quint64 tag = varint();
        if (bad)
            return false;
        number = quint32(tag >> 3);
        switch (tag & 7) {
        case 0:
            varint();
            break;
        case 1:
            skip(8);
            break;
        case 2: {
            const quint64 n = varint();
            if (bad || n > quint64(end - p)) {
                bad = true;
                return false;
            }
            bytes = QByteArray(reinterpret_cast<const char *>(p), qsizetype(n));
            p += n;
            delimited = true;
            break;
        }
        case 5:
            skip(4);
            break;
        default:
            bad = true;
        }
        return !bad;
    }
    void skip(quint64 n) {
        if (n > quint64(end - p))
            bad = true;
        else
            p += n;
    }
};

struct Proof {
    QByteArray key;
    QByteArray signature;
    bool ecdsa = false;
};

bool readProof(const QByteArray &bytes, Proof &out) {
    Reader r(bytes);
    while (!r.done()) {
        quint32 number;
        QByteArray value;
        bool delimited;
        if (!r.field(number, value, delimited))
            return false;
        if (delimited && number == 1)
            out.key = value;
        else if (delimited && number == 2)
            out.signature = value;
    }
    return !out.key.isEmpty() && !out.signature.isEmpty();
}

struct EvpKey {
    EVP_PKEY *key = nullptr;
    explicit EvpKey(const QByteArray &der) {
        const uchar *p = reinterpret_cast<const uchar *>(der.constData());
        key = d2i_PUBKEY(nullptr, &p, long(der.size()));
        // the whole of the bytes must be the key
        if (key && p != reinterpret_cast<const uchar *>(der.constData()) + der.size()) {
            EVP_PKEY_free(key);
            key = nullptr;
        }
    }
    ~EvpKey() { EVP_PKEY_free(key); }
    EvpKey(const EvpKey &) = delete;
    EvpKey &operator=(const EvpKey &) = delete;
};

// SHA-256 with RSA (PKCS#1 v1.5) or ECDSA (DER signature), over the parts in order. RSA keys under 2048 bits are not trusted.
bool signatureHolds(const Proof &proof, const QList<QByteArray> &parts) {
    const EvpKey key(proof.key);
    if (!key.key)
        return false;
    const int type = EVP_PKEY_base_id(key.key);
    if (proof.ecdsa ? type != EVP_PKEY_EC : type != EVP_PKEY_RSA)
        return false;
    if (!proof.ecdsa && EVP_PKEY_bits(key.key) < 2048)
        return false;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx)
        return false;
    bool ok = EVP_DigestVerifyInit(ctx, nullptr, EVP_sha256(), nullptr, key.key) == 1;
    for (const QByteArray &part : parts)
        ok = ok && EVP_DigestVerifyUpdate(ctx, part.constData(), size_t(part.size())) == 1;
    ok = ok && EVP_DigestVerifyFinal(ctx, reinterpret_cast<const uchar *>(proof.signature.constData()), size_t(proof.signature.size())) == 1;
    EVP_MD_CTX_free(ctx);
    return ok;
}

QByteArray sha256(const QByteArray &data) {
    uchar digest[EVP_MAX_MD_SIZE];
    unsigned len = 0;
    if (EVP_Digest(data.constData(), size_t(data.size()), digest, &len, EVP_sha256(), nullptr) != 1)
        return {};
    return QByteArray(reinterpret_cast<const char *>(digest), qsizetype(len));
}

// 16 bytes as 32 letters a-p, high nibble first
QString letters(const QByteArray &sixteen) {
    QString id;
    for (const uchar b : sixteen) {
        id += QChar(u'a' + (b >> 4));
        id += QChar(u'a' + (b & 15));
    }
    return id;
}

Crx::Result refuse(const QString &why) {
    Crx::Result r;
    r.problem = why;
    return r;
}

}

QString Crx::idOfKey(const QByteArray &der) {
    if (der.isEmpty())
        return {};
    const QByteArray hash = sha256(der);
    return hash.size() == 32 ? letters(hash.left(16)) : QString();
}

Crx::Result Crx::verify(const QByteArray &crx, const QString &expectedId) {
    static const QString damaged = QObject::tr("The file from Google is damaged, so nothing was added.");
    if (crx.size() < 12 || !crx.startsWith("Cr24"))
        return refuse(damaged);
    const quint32 version = qFromLittleEndian<quint32>(crx.constData() + 4);
    if (version != 3)
        return refuse(QObject::tr("The file from Google is in an older form that Thyris doesn't trust, so nothing was added."));
    const quint32 headerSize = qFromLittleEndian<quint32>(crx.constData() + 8);
    if (headerSize == 0 || headerSize > (1u << 20) || qint64(headerSize) > crx.size() - 12)
        return refuse(damaged);
    const QByteArray header = crx.mid(12, qsizetype(headerSize));
    const QByteArray archive = crx.mid(12 + qsizetype(headerSize));
    if (archive.isEmpty())
        return refuse(damaged);

    QList<Proof> proofs;
    QByteArray signedData;
    Reader r(header);
    while (!r.done()) {
        quint32 number;
        QByteArray value;
        bool delimited;
        if (!r.field(number, value, delimited))
            return refuse(damaged);
        if (!delimited)
            continue;
        if (number == 2 || number == 3) {
            Proof proof;
            proof.ecdsa = number == 3;
            if (!readProof(value, proof))
                return refuse(damaged);
            proofs.append(proof);
            if (proofs.size() > 16)
                return refuse(damaged);
        } else if (number == 10000) {
            signedData = value;
        }
    }
    if (proofs.isEmpty() || signedData.isEmpty())
        return refuse(damaged);

    // signed_header_data is a SignedData: crx_id (field 1), the first 16 bytes of the SHA-256 of the extension's key
    QByteArray crxId;
    Reader s(signedData);
    while (!s.done()) {
        quint32 number;
        QByteArray value;
        bool delimited;
        if (!s.field(number, value, delimited))
            return refuse(damaged);
        if (delimited && number == 1)
            crxId = value;
    }
    if (crxId.size() != 16)
        return refuse(damaged);
    const QString id = letters(crxId);
    if (id != expectedId)
        return refuse(QObject::tr("The file from Google is for a different extension than the one you chose, so nothing was added."));

    // what the proofs sign
    QByteArray sizeLe(4, 0);
    qToLittleEndian<quint32>(quint32(signedData.size()), sizeLe.data());
    const QList<QByteArray> parts{QByteArray("CRX3 SignedData\0", 16), sizeLe, signedData, archive};
    QByteArray ownKey;
    for (const Proof &proof : std::as_const(proofs)) {
        if (!signatureHolds(proof, parts))
            return refuse(QObject::tr("The file from Google didn't check out, so nothing was added. Try again in a moment."));
        if (sha256(proof.key).left(16) == crxId)
            ownKey = proof.key;
    }
    if (ownKey.isEmpty())
        return refuse(QObject::tr("The file from Google isn't from this extension's maker, so nothing was added."));

    Result ok;
    ok.ok = true;
    ok.id = id;
    ok.key = ownKey;
    ok.zip = archive;
    return ok;
}

namespace {

struct Entry {
    QString name;
    bool dir = false;
    quint16 method = 0;
    quint32 crc = 0;
    quint32 csize = 0;
    quint32 usize = 0;
    quint32 offset = 0;
};

QString badZip() { return QObject::tr("The extension's files can't be opened, so nothing was added."); }

// A name that stays inside the folder: relative, no ".." part, no backslash, no control character, no drive letter
bool safeName(const QString &name) {
    if (name.isEmpty() || name.startsWith(u'/') || name.contains(u'\\') || (name.size() > 1 && name.at(1) == u':'))
        return false;
    for (const QChar c : name)
        if (c.unicode() < 0x20 || c.unicode() == 0x7f)
            return false;
    for (const QString &part : name.split(u'/'))
        if (part == QLatin1String(".."))
            return false;
    return true;
}

}

QString Zip::extract(const QByteArray &zip, const QString &dir, const Limits &limits) {
    const uchar *d = reinterpret_cast<const uchar *>(zip.constData());
    const qint64 size = zip.size();
    // the end-of-central-directory record: in the last 64 KiB + 22 bytes
    qint64 eocd = -1;
    for (qint64 i = size - 22; i >= 0 && i >= size - 22 - 65535; --i)
        if (qFromLittleEndian<quint32>(d + i) == 0x06054b50u) {
            eocd = i;
            break;
        }
    if (eocd < 0)
        return badZip();
    const quint16 count = qFromLittleEndian<quint16>(d + eocd + 10);
    const quint32 dirSize = qFromLittleEndian<quint32>(d + eocd + 12);
    const quint32 dirOffset = qFromLittleEndian<quint32>(d + eocd + 16);
    // zip64 holds files of 4 GiB and more: not an extension
    if (count == 0xffff || dirSize == 0xffffffffu || dirOffset == 0xffffffffu || qint64(dirOffset) + dirSize > eocd)
        return badZip();
    if (count == 0 || count > limits.files)
        return QObject::tr("The extension has too many files, so nothing was added.");

    QList<Entry> entries;
    QSet<QString> seen;
    qint64 total = 0;
    qint64 at = dirOffset;
    for (int i = 0; i < count; ++i) {
        if (at + 46 > qint64(dirOffset) + dirSize || qFromLittleEndian<quint32>(d + at) != 0x02014b50u)
            return badZip();
        const quint16 madeBy = qFromLittleEndian<quint16>(d + at + 4);
        const quint16 flags = qFromLittleEndian<quint16>(d + at + 8);
        Entry e;
        e.method = qFromLittleEndian<quint16>(d + at + 10);
        e.crc = qFromLittleEndian<quint32>(d + at + 16);
        e.csize = qFromLittleEndian<quint32>(d + at + 20);
        e.usize = qFromLittleEndian<quint32>(d + at + 24);
        const quint16 nameLen = qFromLittleEndian<quint16>(d + at + 28);
        const quint16 extraLen = qFromLittleEndian<quint16>(d + at + 30);
        const quint16 commentLen = qFromLittleEndian<quint16>(d + at + 32);
        const quint32 external = qFromLittleEndian<quint32>(d + at + 38);
        e.offset = qFromLittleEndian<quint32>(d + at + 42);
        if (at + 46 + nameLen + extraLen + commentLen > qint64(dirOffset) + dirSize)
            return badZip();
        const QByteArray raw(reinterpret_cast<const char *>(d + at + 46), nameLen);
        at += 46 + nameLen + extraLen + commentLen;
        if (raw.contains('\0'))
            return QObject::tr("The extension has a file name that is not allowed, so nothing was added.");
        e.name = QString::fromUtf8(raw);
        // a symbolic link or any other special file (made on Unix: the mode is the top half of the external attributes)
        if ((madeBy >> 8) == 3) {
            const quint32 type = (external >> 16) & 0170000;
            if (type != 0 && type != 0100000 && type != 0040000)
                return QObject::tr("The extension holds a link or special file, which Thyris does not allow, so nothing was added.");
        }
        e.dir = e.name.endsWith(u'/');
        const QString clean = e.dir ? e.name.chopped(1) : e.name;
        if (!safeName(clean))
            return QObject::tr("The extension has a file that would be put outside its own folder, so nothing was added.");
        if (flags & 1)
            return QObject::tr("The extension's files are locked with a password, so nothing was added.");
        if (!e.dir && e.method != 0 && e.method != 8)
            return badZip();
        // two names that are one file on a case-folding disk are one name here too
        const QString key = QDir::cleanPath(clean).toLower();
        if (seen.contains(key))
            return QObject::tr("The extension names one file twice, so nothing was added.");
        seen.insert(key);
        if (!e.dir) {
            if (e.usize > limits.fileBytes || (total += e.usize) > limits.totalBytes)
                return QObject::tr("The extension is too big, so nothing was added.");
        }
        entries.append(e);
    }

    // every name was fine: unpack
    const QString root = QDir::cleanPath(dir);
    for (const Entry &e : std::as_const(entries)) {
        const QString clean = e.dir ? e.name.chopped(1) : e.name;
        const QString path = QDir::cleanPath(root + u'/' + clean);
        if (!path.startsWith(root + u'/'))
            return QObject::tr("The extension has a file that would be put outside its own folder, so nothing was added.");
        if (e.dir) {
            if (!QDir().mkpath(path))
                return badZip();
            continue;
        }
        const qint64 local = e.offset;
        if (local + 30 > size || qFromLittleEndian<quint32>(d + local) != 0x04034b50u)
            return badZip();
        const qint64 start = local + 30 + qFromLittleEndian<quint16>(d + local + 26) + qFromLittleEndian<quint16>(d + local + 28);
        if (start + e.csize > size)
            return badZip();
        QByteArray data;
        if (e.method == 0) {
            if (e.csize != e.usize)
                return badZip();
            data = QByteArray(reinterpret_cast<const char *>(d + start), qsizetype(e.csize));
        } else {
            data.resize(qsizetype(e.usize));
            z_stream z{};
            if (inflateInit2(&z, -15) != Z_OK)
                return badZip();
            z.next_in = const_cast<Bytef *>(d + start);
            z.avail_in = e.csize;
            z.next_out = reinterpret_cast<Bytef *>(data.data());
            z.avail_out = e.usize;
            // it must end exactly at the size the entry declares: more output than that is a bomb in the making
            const int code = e.usize == 0 && e.csize == 0 ? Z_STREAM_END : inflate(&z, Z_FINISH);
            const bool whole = code == Z_STREAM_END && z.total_out == e.usize;
            inflateEnd(&z);
            if (!whole)
                return badZip();
        }
        if (quint32(crc32(0, reinterpret_cast<const Bytef *>(data.constData()), uInt(data.size()))) != e.crc)
            return badZip();
        if (!QDir().mkpath(QFileInfo(path).absolutePath()))
            return badZip();
        QFile out(path);
        if (QFileInfo::exists(path) || !out.open(QIODevice::WriteOnly) || out.write(data) != data.size())
            return badZip();
    }
    return {};
}
