#pragma once

#include <QObject>
#include <QString>
#include <qqmlintegration.h>

// Reader view (PLAN.md 3.9): the sources of Mozilla's Readability.js and Readability-readerable.js (readability/,
// Apache-2.0, unmodified), built into the app, for Reader.js to run in a page's script world.
class Readability : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // defines isProbablyReaderable(document)
    Q_PROPERTY(QString readerable READ readerable CONSTANT)
    // defines isProbablyReaderable and Readability
    Q_PROPERTY(QString script READ script CONSTANT)
public:
    using QObject::QObject;
    QString readerable() const;
    QString script() const;
};
