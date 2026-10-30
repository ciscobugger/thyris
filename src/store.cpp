#include "store.h"

#include <QDir>
#include <QFile>
#include <QJSValue>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>

Store::Store(QObject *parent) : QObject(parent) {
    m_dataDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/browser");
    QDir().mkpath(m_dataDir);
    // history and the session hold every URL visited: owner only, like the Chromium profile beside them
    QFile::setPermissions(m_dataDir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
}

QVariant Store::load(const QString &name) const {
    QFile file(m_dataDir + u'/' + name + QStringLiteral(".json"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).toVariant();
}

namespace {
// Objects from QML arrive as a QJSValue, which QJsonDocument does not read (it writes null): converted, also inside a map
// or a list. Code qmlcachegen compiled for the release build hands over an object literal as a map of QJSValues
// (2026-10-01: Saved.save wrote {"pages":null,"threads":null} there, the dev build's interpreted QML a whole object).
QVariant plain(const QVariant &value) {
    if (value.metaType() == QMetaType::fromType<QJSValue>())
        return value.value<QJSValue>().toVariant(QJSValue::ConvertJSObjects);
    if (value.metaType() == QMetaType::fromType<QVariantMap>()) {
        QVariantMap map = value.toMap();
        for (QVariant &v : map)
            v = plain(v);
        return map;
    }
    if (value.metaType() == QMetaType::fromType<QVariantList>()) {
        QVariantList list = value.toList();
        for (QVariant &v : list)
            v = plain(v);
        return list;
    }
    return value;
}
}

bool Store::write(const QString &name, const QVariant &plainValue) const {
    QSaveFile file(m_dataDir + u'/' + name + QStringLiteral(".json"));
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument::fromVariant(plainValue).toJson(QJsonDocument::Compact));
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return file.commit();
}

bool Store::save(const QString &name, const QVariant &value) const {
    {
        QMutexLocker lock(&m_genLock);
        ++m_gen[name];
    }
    QMutexLocker write(&m_writeLock);
    return this->write(name, plain(value));
}

void Store::saveLater(const QString &name, const QVariant &value) {
    quint64 gen;
    {
        QMutexLocker lock(&m_genLock);
        gen = ++m_gen[name];
    }
    // converted here, where the QJSValues live; the worker only serialises and writes
    QThreadPool::globalInstance()->start([this, name, gen, copy = plain(value)] {
        QMutexLocker write(&m_writeLock);
        {
            QMutexLocker lock(&m_genLock);
            if (m_gen.value(name) != gen)
                return;
        }
        this->write(name, copy);
    });
}

Store::~Store() {
    QThreadPool::globalInstance()->waitForDone();
}
