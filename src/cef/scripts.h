#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

// The scripts a page runs in every document it loads, as WebEngineScriptCollection holds them for Opsis's QML: a view's
// own and its profile's. Each is a map { name, sourceCode, injectionPoint (0 deferred, 1 document ready, 2 document
// creation), worldId (0 the page's own, 1 Opsis's), runsOnSubFrames }. PageItem puts them into the page.
class ScriptCollection : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList collection READ collection WRITE setCollection NOTIFY collectionChanged)
public:
    using QObject::QObject;
    QVariantList collection() const { return m_scripts; }
    void setCollection(const QVariantList &scripts);
    Q_INVOKABLE void insert(const QVariant &scriptOrList);
    Q_INVOKABLE void remove(const QVariantMap &script);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QVariantList find(const QString &name) const;

signals:
    void collectionChanged();

private:
    QVariantList m_scripts;
};
