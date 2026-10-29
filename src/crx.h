#pragma once

#include <QByteArray>
#include <QString>

// A Chrome extension file (.crx, format 3) checked before anything in it is unpacked, and the unpacking of its zip.
// Chromium's own rules (components/crx_file/crx_verifier.cc), with OpenSSL doing the cryptography:
//   "Cr24", version 3, the header's size, the header (a CrxFileHeader protobuf), then the zip archive.
//   Every proof in the header (sha256_with_rsa, sha256_with_ecdsa) must hold over
//   "CRX3 SignedData\0" + the size of signed_header_data (4 bytes, little endian) + signed_header_data + the archive,
//   and one of the keys must be the extension's own: the first 16 bytes of its SHA-256 are the crx_id in
//   signed_header_data. The extension's id is those 16 bytes written with the letters a to p.
namespace Crx {

struct Result {
    bool ok = false;
    QString problem;        // when !ok: what is wrong, in words for the person
    QString id;             // the extension's id, 32 letters a-p
    QByteArray key;         // its public key (DER), what a manifest's "key" holds in base64
    QByteArray zip;         // the archive, only when ok
};

// The id of the extension with public key `der` (SubjectPublicKeyInfo), or "" when it is empty
QString idOfKey(const QByteArray &der);

// `crx` is the whole file. `expectedId` is the id the person asked for: a file for another id is refused, however well signed.
Result verify(const QByteArray &crx, const QString &expectedId);

}

// A zip archive unpacked into a folder, with every name checked first: nothing can land outside the folder.
namespace Zip {

struct Limits {
    qint64 files = 5000;
    qint64 fileBytes = 128ll << 20;     // one file, unpacked
    qint64 totalBytes = 256ll << 20;    // all of them, unpacked
};

// "" when it was unpacked into `dir` (which exists and is empty), else why not, in words for the person. Refused whole, with
// nothing kept, for an absolute path, a ".." part, a symbolic link or other special file, an encrypted or unknown-method
// entry, two entries of one name, a size or checksum that does not match, or more than `limits` allow.
QString extract(const QByteArray &zip, const QString &dir, const Limits &limits = Limits());

}
