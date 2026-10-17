#include "readability.h"

#include <QFile>

static QString source(const char *name) {
    QFile f(QStringLiteral(":/readability/") + QLatin1String(name));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

QString Readability::readerable() const {
    static const QString s = source("Readability-readerable.js");
    return s;
}

QString Readability::script() const {
    static const QString s = source("Readability-readerable.js") + u'\n' + source("Readability.js");
    return s;
}
