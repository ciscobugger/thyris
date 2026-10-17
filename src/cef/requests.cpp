#include "requests.h"

#include "pageitem.h"

#include <QFile>
#include <QFileInfo>
#include <QSet>

void NewWindowRequest::openIn(QObject *view) {
    target = qobject_cast<PageItem *>(view);
}

// files of this run's downloads still coming, so two downloads of one name at once get two names
static QSet<QString> &comingFiles() {
    static QSet<QString> files;
    return files;
}

// `name` free in `directory`: neither it nor its part-file there, nor another download's; else "<stem> (n)<ext>", the
// extension being the last one ("archive.tar.gz" keeps ".tar.gz", as Chromium's)
static QString uniqueName(const QString &directory, const QString &name) {
    const auto taken = [&](const QString &n) {
        const QString path = directory + QLatin1Char('/') + n;
        return QFileInfo::exists(path) || QFileInfo::exists(path + QStringLiteral(".download")) || comingFiles().contains(path);
    };
    if (!taken(name))
        return name;
    qsizetype dot = name.lastIndexOf(QLatin1Char('.'));
    if (dot > 0 && name.mid(dot - 4, 4).compare(u".tar", Qt::CaseInsensitive) == 0)
        dot -= 4;
    if (dot <= 0)
        dot = name.size();
    const QString stem = name.left(dot), extension = name.mid(dot);
    for (int n = 1;; ++n) {
        const QString candidate = QStringLiteral("%1 (%2)%3").arg(stem).arg(n).arg(extension);
        if (!taken(candidate))
            return candidate;
    }
}

DownloadRequest::~DownloadRequest() {
    comingFiles().remove(m_directory + QLatin1Char('/') + m_fileName);
}

void DownloadRequest::setDownloadDirectory(const QString &directory) {
    if (m_accepted || directory == m_directory)
        return;
    m_directory = directory;
    const QString name = uniqueName(directory, suggestedFileName.isEmpty() ? QStringLiteral("download") : suggestedFileName);
    emit downloadDirectoryChanged();
    if (name != m_fileName) {
        m_fileName = name;
        emit downloadFileNameChanged();
    }
}

void DownloadRequest::accept() {
    if (m_accepted || !start)
        return;
    m_accepted = true;
    comingFiles().insert(m_directory + QLatin1Char('/') + m_fileName);
    std::exchange(start, nullptr)(partPath());
    if (m_state == Requested)
        setState(InProgress);
}

// Chromium cancels only a download in progress: an interrupted one is let go here, its part-file left (as Qt's)
void DownloadRequest::cancel() {
    if (m_state == Interrupted) {
        setState(Cancelled);
        if (released)
            std::exchange(released, nullptr)();
        return;
    }
    control(Cancel);
}

void DownloadRequest::setState(int state) {
    if (state == m_state)
        return;
    const bool finished = isFinished();
    m_state = state;
    if (isFinished())
        comingFiles().remove(m_directory + QLatin1Char('/') + m_fileName);
    emit stateChanged();
    if (finished != isFinished())
        emit isFinishedChanged();
}

void DownloadRequest::update(const Update &u) {
    if (!m_accepted || isFinished())
        return;
    if (u.total != m_total) {
        m_total = u.total;
        emit totalBytesChanged();
    }
    if (u.received != m_received) {
        m_received = u.received;
        emit receivedBytesChanged();
    }
    if (u.paused != m_paused) {
        m_paused = u.paused;
        emit isPausedChanged();
    }
    if (u.reason != m_reason) {
        m_reason = u.reason;
        emit interruptReasonChanged();
    }
    if (u.complete) {
        // the part-file becomes the file; a file of that name made meanwhile keeps it under the part's name
        const QString file = m_directory + QLatin1Char('/') + m_fileName;
        if (!QFileInfo::exists(file))
            QFile::rename(partPath(), file);
        setState(Completed);
    } else if (u.canceled) {
        QFile::remove(partPath());
        setState(Cancelled);
    } else if (u.interrupted) {
        setState(Interrupted);
    } else if (u.inProgress) {
        setState(InProgress);
    }
}
