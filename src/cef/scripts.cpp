#include "scripts.h"

#include <QJSValue>

static bool same(const QVariantMap &a, const QVariantMap &b) {
    return a.value(QStringLiteral("name")) == b.value(QStringLiteral("name")) && a.value(QStringLiteral("sourceCode")) == b.value(QStringLiteral("sourceCode"))
        && a.value(QStringLiteral("worldId")) == b.value(QStringLiteral("worldId")) && a.value(QStringLiteral("injectionPoint")) == b.value(QStringLiteral("injectionPoint"));
}

void ScriptCollection::setCollection(const QVariantList &scripts) {
    m_scripts = scripts;
    emit collectionChanged();
}

void ScriptCollection::insert(const QVariant &scriptOrList) {
    // a script made by WebEngine.script() comes from QML as a JS object (a QJSValue), a list of them as an array
    const QVariant value = scriptOrList.typeId() == qMetaTypeId<QJSValue>() ? scriptOrList.value<QJSValue>().toVariant() : scriptOrList;
    if (value.typeId() == QMetaType::QVariantList)
        m_scripts += value.toList();
    else
        m_scripts.append(value.toMap());
    emit collectionChanged();
}

void ScriptCollection::remove(const QVariantMap &script) {
    const auto n = m_scripts.size();
    m_scripts.removeIf([&](const QVariant &s) { return same(s.toMap(), script); });
    if (m_scripts.size() != n)
        emit collectionChanged();
}

void ScriptCollection::clear() {
    if (m_scripts.isEmpty())
        return;
    m_scripts.clear();
    emit collectionChanged();
}

QVariantList ScriptCollection::find(const QString &name) const {
    QVariantList out;
    for (const QVariant &s : m_scripts)
        if (s.toMap().value(QStringLiteral("name")).toString() == name)
            out.append(s);
    return out;
}
