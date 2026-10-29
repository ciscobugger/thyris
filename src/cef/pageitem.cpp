#include "pageitem.h"

#include "cookies.h"
#include "input.h"
#include "runtime.h"
#include "scripts.h"

// EGL's headers pull in Xlib otherwise, and its macros (None, Bool, Status) break Qt's and CEF's
#define EGL_NO_X11
#include <dlfcn.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTimer>
#include <QDrag>
#include <QDropEvent>
#include <QFocusEvent>
#include <QGuiApplication>
#include <QBuffer>
#include <QClipboard>
#include <QHash>
#include <QHoverEvent>
#include <QImage>
#include <QInputMethodEvent>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMimeData>
#include <QMouseEvent>
#include <QMutex>
#include <QSemaphore>
#include <QSet>
#include <QStyleHints>
#include <QWheelEvent>
#include <QNativeGestureEvent>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QPixmap>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSGSimpleTextureNode>
#include <QScreen>
#include <QStandardPaths>
#include <QtQuick/qsgtexture_platform.h>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <drm/drm_fourcc.h>
#include <map>
#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_context.h"
#include "include/cef_values.h"
#include "include/cef_cookie.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "devtoolsbridge.h"
#include "include/cef_dialog_handler.h"
#include "include/cef_download_handler.h"
#include "include/cef_drag_data.h"
#include "include/cef_find_handler.h"
#include "include/cef_image.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_navigation_entry.h"
#include "include/cef_focus_handler.h"
#include "include/cef_keyboard_handler.h"
#include "include/cef_parser.h"
#include "include/cef_request_handler.h"
#include "include/cef_ssl_info.h"
#include "include/cef_resource_handler.h"
#include "include/cef_render_handler.h"
#include "include/cef_task.h"
#include "include/wrapper/cef_closure_task.h"

#include <chrono>
#include <csignal>


namespace {

// Chromium's spelling suggestions for a right-clicked misspelled word
QStringList suggestions(CefRefPtr<CefContextMenuParams> params) {
    std::vector<CefString> words;
    params->GetDictionarySuggestions(words);
    QStringList out;
    for (const CefString &w : words)
        out << QString::fromStdString(w.ToString());
    return out;
}

// a page's profile as CEF's request context (the profiles section below)
CefRefPtr<CefRequestContext> contextOf(QObject *profile);
// cookies may have changed: SiteData lists them again (the cookies section below)
void cookiesTouched();

// OPSIS_CEF_TRACE (PageItem::traceFrame)
const bool traced = qEnvironmentVariableIsSet("OPSIS_CEF_TRACE");

// The system's pid of this browser's page process with `--renderer-client-id=<id>` (the process only knows the sandbox's
// pid): a descendant of this process, so another Opsis or Chrome with the same id is never taken. 0 when none is found.
static qint64 rendererPid(const QByteArray &id) {
    if (id.isEmpty())
        return 0;
    const QByteArray wanted = "--renderer-client-id=" + id;
    const qint64 self = QCoreApplication::applicationPid();
    const auto parentOf = [](qint64 pid) -> qint64 {
        QFile f(QStringLiteral("/proc/%1/stat").arg(pid));
        if (!f.open(QIODevice::ReadOnly))
            return 0;
        const QByteArray s = f.readAll();
        const qsizetype close = s.lastIndexOf(')');      // the name may hold spaces and parentheses
        const QList<QByteArray> fields = s.mid(close + 2).split(' ');
        return fields.size() > 1 ? fields.at(1).toLongLong() : 0;
    };
    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        bool number = false;
        const qint64 pid = entry.toLongLong(&number);
        if (!number)
            continue;
        QFile f(QStringLiteral("/proc/%1/cmdline").arg(pid));
        if (!f.open(QIODevice::ReadOnly))
            continue;
        // Chromium rewrites its processes' titles: the arguments are one string, spaces between
        const QByteArray line = f.readAll().replace('\0', ' ') + ' ';
        if (!line.contains("--type=renderer ") || !line.contains(wanted + ' '))
            continue;
        for (qint64 up = parentOf(pid), hops = 0; up > 1 && hops < 6; up = parentOf(up), ++hops)
            if (up == self)
                return pid;
    }
    return 0;
}
// Diagnosis (2026-10-08, the gap to Chrome on Speedometer): OPSIS_CEF_NODEVTOOLS opens pages without Opsis's DevTools
// session (its world, bridge and scripts; runJavaScript then never answers), OPSIS_CEF_NOSCRIPTS without the profile's and
// the view's scripts
const bool noDevtools = qEnvironmentVariableIsSet("OPSIS_CEF_NODEVTOOLS");
const bool noScripts = qEnvironmentVariableIsSet("OPSIS_CEF_NOSCRIPTS");
// The native route (~/book4-edge/opsis-beat-chrome-plan.md, stage 1): Opsis's scripts, its world and runJavaScript go
// through browser-page's render process handler (src/cef/pageprocess.cpp) and CEF's process messages, with no DevTools
// session, whose Page domain cost ~0.6 on Speedometer (2026-10-08). It needs the engine's Opsis world
// (~/dev/tacit-web/cef-tacit-opsis-world.patch); on an engine without it, and with OPSIS_CEF_DEVTOOLS (to compare),
// the DevTools route below.
// The engine carries Tacit's patches of 2026-10-08 (Opsis's world, ~/dev/tacit-web/cef-tacit-opsis-world.patch, which
// exports the probe, and Opsis's navigation, cef-tacit-navigation.patch: they ship together)
const bool tacitEngine = [] {
    const auto probe = reinterpret_cast<int (*)()>(dlsym(RTLD_DEFAULT, "cef_tacit_opsis_world"));
    return probe && probe();
}();
const bool nativeRoute = tacitEngine && !qEnvironmentVariableIsSet("OPSIS_CEF_DEVTOOLS");
// and which debug domain costs it: OPSIS_CEF_NORUNTIME skips Runtime.enable, OPSIS_CEF_NOPAGE Page.enable
const bool noRuntimeDomain = qEnvironmentVariableIsSet("OPSIS_CEF_NORUNTIME");
const bool noPageDomain = qEnvironmentVariableIsSet("OPSIS_CEF_NOPAGE");
// CEF keeps its own clock unless OPSIS_CEF_BEAT is set (PageItem::beginFrame)
const bool ownBeat = !qEnvironmentVariableIsSet("OPSIS_CEF_BEAT");
qint64 nowNs() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// The GL context that copies frames. It lives on CEF's UI thread, where every page's frames arrive, and shares its
// textures with every window's scene graph. Made once and kept until the process ends.
class Copier {
public:
    static Copier &get() {
        static Copier copier;
        return copier;
    }
    // GUI thread, before the first shared frame: the surface the context is made current on
    void prepare() {
        if (m_surface)
            return;
        m_surface = new QOffscreenSurface;
        m_surface->setFormat(QOpenGLContext::globalShareContext()->format());
        m_surface->create();
    }
    // CEF's UI thread. False when the context cannot be made or lacks the dmabuf import.
    bool current() {
        if (m_failed)
            return false;
        if (!m_context) {
            m_context = new QOpenGLContext;
            m_context->setShareContext(QOpenGLContext::globalShareContext());
            m_context->setFormat(m_surface->format());
            m_failed = !m_context->create() || !m_context->makeCurrent(m_surface);
            if (!m_failed) {
                gl = m_context->extraFunctions();
                display = eglGetCurrentDisplay();
                createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
                destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
                imageTarget = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
                    eglGetProcAddress("glEGLImageTargetTexture2DOES"));
                m_failed = display == EGL_NO_DISPLAY || !createImage || !destroyImage || !imageTarget;
            }
            if (m_failed) {
                qWarning("PageItem: no GL context to copy the page's frames with; the page stays empty");
                return false;
            }
            gl->glGenFramebuffers(1, &readFbo);
            gl->glGenFramebuffers(1, &drawFbo);
        }
        return QOpenGLContext::currentContext() == m_context || m_context->makeCurrent(m_surface);
    }

    QOpenGLExtraFunctions *gl = nullptr;
    EGLDisplay display = EGL_NO_DISPLAY;
    PFNEGLCREATEIMAGEKHRPROC createImage = nullptr;
    PFNEGLDESTROYIMAGEKHRPROC destroyImage = nullptr;
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC imageTarget = nullptr;
    GLuint readFbo = 0, drawFbo = 0;

private:
    QOffscreenSurface *m_surface = nullptr;
    QOpenGLContext *m_context = nullptr;
    bool m_failed = false;
};

void deleteTextures(std::array<GLuint, 3> textures) {
    if (Copier::get().current())
        Copier::get().gl->glDeleteTextures(3, textures.data());
}

bool sharedFrames(QQuickWindow *window) {
    return qgetenv("OPSIS_CEF_FRAMES") != "cpu" && QOpenGLContext::globalShareContext()
        && window->rendererInterface()->graphicsApi() == QSGRendererInterface::OpenGL;
}

}

// A page's frames, between CEF's UI thread (write) and the scene graph's render thread (take).
// Shared frames: three textures. CEF takes its buffer back when the callback returns, so the frame is copied there and
// then, on the graphics chip, into the texture nobody reads (`back`); finished, it becomes `ready`, and the render
// thread swaps `ready` for the one it shows (`front`) when it next draws.
class PageFrames {
public:
    ~PageFrames() {
        const std::array<GLuint, 3> textures{m_slots[0].texture, m_slots[1].texture, m_slots[2].texture};
        if (textures[0] || textures[1] || textures[2])
            CefPostTask(TID_UI, base::BindOnce(&deleteTextures, textures));     // refused once CEF has stopped
    }

    void write(const CefAcceleratedPaintInfo &info) {
        const qint64 began = traced ? nowNs() : 0;
        Copier &copier = Copier::get();
        if (!copier.current())
            return;
        QOpenGLExtraFunctions *gl = copier.gl;
        const cef_rect_t &visible = info.extra.visible_rect;
        const auto &plane = info.planes[0];
        // a frame from the middle of a resize whose shown part reaches past its own buffer: copying it would read outside
        // the buffer, so it is skipped and the last frame stays on screen
        if (visible.width <= 0 || visible.height <= 0 || visible.x < 0 || visible.y < 0
            || visible.x + visible.width > info.extra.coded_size.width || visible.y + visible.height > info.extra.coded_size.height) {
            if (traced)
                std::fprintf(stderr, "cef trace: frame skipped: visible %d,%d %dx%d, coded %dx%d\n", visible.x, visible.y, visible.width,
                             visible.height, info.extra.coded_size.width, info.extra.coded_size.height);
            return;
        }
        if (traced) {
            static cef_rect_t lastVisible{}, lastContent{};
            const cef_rect_t &content = info.extra.content_rect;
            if (visible.width != lastVisible.width || visible.height != lastVisible.height || content.width != lastContent.width
                || content.height != lastContent.height || content.x != lastContent.x || content.y != lastContent.y)
                std::fprintf(stderr, "cef trace: frame coded %dx%d visible %d,%d %dx%d content %d,%d %dx%d source %s%dx%d\n",
                             info.extra.coded_size.width, info.extra.coded_size.height, visible.x, visible.y, visible.width,
                             visible.height, content.x, content.y, content.width, content.height,
                             info.extra.has_source_size ? "" : "(none) ", info.extra.source_size.width, info.extra.source_size.height);
            lastVisible = visible;
            lastContent = content;
        }
        EGLint attributes[20];
        int n = 0;
        const auto put = [&](EGLint name, EGLint value) { attributes[n++] = name; attributes[n++] = value; };
        put(EGL_WIDTH, info.extra.coded_size.width);
        put(EGL_HEIGHT, info.extra.coded_size.height);
        put(EGL_LINUX_DRM_FOURCC_EXT, info.format == CEF_COLOR_TYPE_BGRA_8888 ? DRM_FORMAT_ARGB8888 : DRM_FORMAT_ABGR8888);
        put(EGL_DMA_BUF_PLANE0_FD_EXT, plane.fd);
        put(EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGLint(plane.offset));
        put(EGL_DMA_BUF_PLANE0_PITCH_EXT, EGLint(plane.stride));
        if (info.modifier != DRM_FORMAT_MOD_INVALID) {
            put(EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGLint(info.modifier & 0xffffffff));
            put(EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGLint(info.modifier >> 32));
        }
        attributes[n] = EGL_NONE;
        const EGLImageKHR image = copier.createImage(copier.display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attributes);
        if (image == EGL_NO_IMAGE_KHR) {
            if (!m_warned)
                qWarning("PageItem: the page's frame cannot be imported (EGL 0x%x)", eglGetError());
            m_warned = true;
            return;
        }
        GLuint source = 0;
        gl->glGenTextures(1, &source);
        gl->glBindTexture(GL_TEXTURE_2D, source);
        copier.imageTarget(GL_TEXTURE_2D, image);

        Slot &back = m_slots[m_back];       // m_back changes on this thread only
        const QSize size(visible.width, visible.height);
        bool fresh = false;
        if (back.size != size) {
            if (!back.texture)
                gl->glGenTextures(1, &back.texture);
            gl->glBindTexture(GL_TEXTURE_2D, back.texture);
            gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size.width(), size.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            back.size = size;
            fresh = true;
        }
        gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, copier.readFbo);
        gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, source, 0);
        gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, copier.drawFbo);
        gl->glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, back.texture, 0);
        // a texture made for a new size starts clear, never with what graphics memory held before (it showed as streaks)
        if (fresh) {
            gl->glClearColor(0, 0, 0, 0);
            gl->glClear(GL_COLOR_BUFFER_BIT);
        }
        // a frame the graphics chip cannot read from is skipped: the last one stays on screen
        if (const GLenum status = gl->glCheckFramebufferStatus(GL_READ_FRAMEBUFFER); status != GL_FRAMEBUFFER_COMPLETE) {
            if (traced)
                std::fprintf(stderr, "cef trace: frame skipped: its framebuffer is incomplete (0x%x)\n", status);
            gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
            gl->glDeleteTextures(1, &source);
            copier.destroyImage(copier.display, image);
            return;
        }
        gl->glBlitFramebuffer(visible.x, visible.y, visible.x + visible.width, visible.y + visible.height,
                              0, 0, size.width(), size.height(), GL_COLOR_BUFFER_BIT, GL_NEAREST);
        // done before CEF has its buffer back, and before the scene graph's context reads the texture
        gl->glFinish();
        gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
        gl->glDeleteTextures(1, &source);
        copier.destroyImage(copier.display, image);

        if (traced) {
            // the time CEF's UI thread spends copying, every 120 frames: it takes input there too
            static qint64 sum = 0, worst = 0;
            static int count = 0;
            const qint64 took = nowNs() - began;
            sum += took;
            worst = qMax(worst, took);
            if (++count == 120) {
                std::fprintf(stderr, "cef trace: frame copy %.2f ms on average, %.2f ms at worst\n", sum / 120 / 1e6, worst / 1e6);
                sum = worst = 0;
                count = 0;
            }
        }
        QMutexLocker lock(&m_lock);
        std::swap(m_back, m_ready);
        m_fresh = true;
    }

    // through memory: BGRA, premultiplied, CEF's own again when the callback returns
    void write(const void *pixels, int width, int height) {
        QImage image = QImage(static_cast<const uchar *>(pixels), width, height, width * 4,
                              QImage::Format_ARGB32_Premultiplied).copy();
        QMutexLocker lock(&m_lock);
        m_image = std::move(image);
        m_fresh = true;
    }

    struct Shown {
        GLuint texture = 0;     // shared frames
        QSize size;
        QImage image;           // through memory; null unless a new one came
    };
    Shown take() {
        QMutexLocker lock(&m_lock);
        Shown shown;
        if (m_fresh && !m_image.isNull())
            shown.image = m_image;
        else if (m_fresh)
            std::swap(m_front, m_ready);
        m_fresh = false;
        shown.texture = m_slots[m_front].texture;
        shown.size = m_slots[m_front].size;
        return shown;
    }

private:
    struct Slot {
        GLuint texture = 0;
        QSize size;
    };
    QMutex m_lock;
    Slot m_slots[3];
    int m_back = 0, m_ready = 1, m_front = 2;
    bool m_fresh = false;       // `ready` (or m_image) is newer than what is shown
    QImage m_image;
    bool m_warned = false;
};

namespace {
// Opsis's own script world in every document, named "opsis": the page's scripts cannot see it. `__opsis` is the
// binding back to this process (Runtime.addBinding). The main frame says which context is its world (for
// runJavaScript there) and reports the document's size and scroll position, one report a frame at most. In every frame,
// Qt WebChannel's transport for Opsis's scripts in this world (Logins.js sends raw WebChannel messages): each message
// goes over the binding to the view's webChannel (the shim's WebEngineView.qml), waiting for the binding if it is late.
const char *const kWorldScript = R"JS(if (typeof qt === 'undefined') self.qt = { webChannelTransport: { send: function send(m, tries) {
    if (typeof __opsis === 'function') __opsis(JSON.stringify({ k: 'channel', m: m }));
    else if ((tries || 0) < 50) setTimeout(() => send(m, (tries || 0) + 1), 10);
} } };
(function start(tries) {
    if (self !== top) return;
    // in a new document the binding can arrive just after this script runs
    if (typeof __opsis !== 'function') { if (tries < 50) setTimeout(() => start(tries + 1), 0); return; }
    __opsis(JSON.stringify({ k: 'ctx' }));
    const send = () => { try { const d = document.documentElement;
        __opsis(JSON.stringify({ k: 'scroll', x: scrollX, y: scrollY, w: d.scrollWidth, h: d.scrollHeight })); } catch (e) {} };
    let t = 0;
    const soon = () => { if (!t) t = requestAnimationFrame(() => { t = 0; send(); }); };
    addEventListener('scroll', soon, { passive: true });
    addEventListener('resize', soon);
    addEventListener('load', soon);
    const watch = () => { soon(); new ResizeObserver(soon).observe(document.documentElement); };
    if (document.readyState === 'loading') addEventListener('DOMContentLoaded', watch); else watch();
})(0);)JS";

// The clipboard (2026-10-20, Discord: copy and paste between Thyris and every other app failed both ways). The engine
// runs on Wayland on a connection of its own, which never has the keyboard, and Wayland gives the clipboard only to the
// app that has it: this window. In Opsis's world in every frame this script tells the page's item what a copy or a cut
// put there (PageItem::copiedInPage); a paste comes the other way (kPasteScript).
const char *const kClipboardScript = R"JS((() => {
    const tell = d => {
        if (d && (d.text || d.html || d.png) && typeof __opsis === 'function')
            __opsis(JSON.stringify({ k: 'clip', text: d.text || '', html: d.html || '', png: d.png || '' }));
    };
    const focused = () => {
        let e = document.activeElement;
        while (e && e.shadowRoot && e.shadowRoot.activeElement) e = e.shadowRoot.activeElement;
        return e;
    };
    // what a copy takes when the page leaves it to the engine: a field's selected text (never a password's), else the
    // selection as text and HTML
    const selected = () => {
        const e = focused();
        if (e instanceof HTMLInputElement || e instanceof HTMLTextAreaElement) {
            if (e.type === 'password') return {};
            try { return { text: e.value.slice(e.selectionStart, e.selectionEnd) }; } catch (x) { return {}; }
        }
        const s = getSelection();
        if (!s || s.isCollapsed) return {};
        const box = document.createElement('div');
        for (let i = 0; i < s.rangeCount; i++) box.appendChild(s.getRangeAt(i).cloneContents());
        return { text: s.toString(), html: box.innerHTML };
    };
    // the page's own handlers come between: what one of them set (and kept from the engine) is what was copied
    for (const type of ['copy', 'cut']) {
        let open = null, before = {};
        addEventListener(type, e => {
            if (!e.isTrusted) return;
            open = e;
            before = selected();
            // a page that stops the event short of the window: the selection as it was
            setTimeout(() => { if (open === e) { open = null; if (!e.defaultPrevented) tell(before); } }, 0);
        }, true);
        addEventListener(type, e => {
            if (open !== e) return;
            open = null;
            const d = e.clipboardData;
            tell(e.defaultPrevented ? { text: d ? d.getData('text/plain') : '', html: d ? d.getData('text/html') : '' } : before);
        });
    }
    // what a page's own Copy button wrote (kClipboardPageScript), taken only while the person has just pressed something
    addEventListener('thyris-clipboard', e => {
        if (!navigator.userActivation || !navigator.userActivation.isActive) return;
        try { tell(JSON.parse(e.detail)); } catch (x) {}
    });
})();)JS";
// In the page's own world in every frame: navigator.clipboard, which a page's Copy button calls, tells Opsis's world
// what it wrote once the engine has taken it
const char *const kClipboardPageScript = R"JS((() => {
    const c = navigator.clipboard;
    if (!c || typeof c.writeText !== 'function') return;
    const tell = d => dispatchEvent(new CustomEvent('thyris-clipboard', { detail: JSON.stringify(d) }));
    const ownWriteText = c.writeText, ownWrite = c.write;
    const base64 = blob => new Promise(done => {
        const r = new FileReader();
        r.onload = () => done(String(r.result).split(',')[1] || '');
        r.onerror = () => done('');
        r.readAsDataURL(blob);
    });
    const read = async items => {
        const d = {};
        for (const item of items || [])
            for (const type of item.types) {
                const blob = await item.getType(type);
                if (type === 'text/plain') d.text = await blob.text();
                else if (type === 'text/html') d.html = await blob.text();
                else if (type === 'image/png') d.png = await base64(blob);
            }
        return d;
    };
    Object.defineProperty(c, 'writeText', { configurable: true, writable: true, value: function writeText(text) {
        return ownWriteText.call(c, text).then(r => { tell({ text: String(text) }); return r; });
    } });
    if (typeof ownWrite === 'function')
        Object.defineProperty(c, 'write', { configurable: true, writable: true, value: function write(items) {
            return ownWrite.call(c, items).then(r => { read(items).then(tell, () => {}); return r; });
        } });
})();)JS";
// The Chrome Web Store's own Add to Chrome (Discord 2026-10-29, Mustiya: Thyris closed itself): the engine's install
// dialog looks for a window to sit in, Thyris draws pages without one, and all of Thyris crashed. In the page's own world
// on the store, its install calls never reach the engine: they answer "cancelled", which leaves the button as it was, and
// tell Opsis's world, which opens Thyris's own Add to Thyris ask while the person has just pressed something. The
// store's API is not there yet when a new document's scripts run, so it is taken over again when the document is read
// and at every press, before the store's own handlers (an install from the packaged 0.1.4-18 still crashed)
const char *const kStorePageScript = R"JS((() => {
    if (location.hostname !== 'chromewebstore.google.com'
        && !(location.hostname === 'chrome.google.com' && location.pathname.startsWith('/webstore')))
        return;
    const install = function () {
        dispatchEvent(new CustomEvent('thyris-store-add'));
        const done = Array.prototype.find.call(arguments, a => typeof a === 'function');
        if (done) { setTimeout(() => done('user_cancelled'), 0); return; }
        return Promise.resolve('user_cancelled');
    };
    const take = () => {
        const api = self.chrome && chrome.webstorePrivate;
        if (!api) return;
        for (const name of ['beginInstallWithManifest3', 'install'])
            if (typeof api[name] === 'function' && api[name] !== install)
                Object.defineProperty(api, name, { configurable: true, writable: true, value: install });
    };
    take();
    addEventListener('DOMContentLoaded', take);
    for (const type of ['pointerdown', 'mousedown', 'keydown', 'click'])
        addEventListener(type, take, true);
})();)JS";
const char *const kStoreScript = R"JS(addEventListener('thyris-store-add', () => {
    if (self === top && navigator.userActivation && navigator.userActivation.isActive && typeof __opsis === 'function')
        __opsis(JSON.stringify({ k: 'storeAdd' }));
});)JS";
// A paste from the desktop's clipboard (PageItem::pasteFromDesktop), called with what it holds, in the frame with the
// focus: the page's own paste handlers first (a chat takes a picture, an editor its HTML); left to the engine, the text
// goes in where the caret is, as a paste puts it (never the HTML: the page's handlers clean that, the engine would not)
const char *const kPasteScript = R"JS((p => {
    let e = document.activeElement;
    while (e && e.shadowRoot && e.shadowRoot.activeElement) e = e.shadowRoot.activeElement;
    const at = e || document.body || document.documentElement;
    const data = new DataTransfer();
    if (p.text) data.setData('text/plain', p.text);
    if (p.html) data.setData('text/html', p.html);
    if (p.png) data.items.add(new File([Uint8Array.from(atob(p.png), c => c.charCodeAt(0))], 'image.png', { type: 'image/png' }));
    if (at.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true, composed: true })) && p.text)
        document.execCommand('insertText', false, p.text);
}))JS";
// a picture bigger than this stays on the desktop's clipboard (it goes to the page as text in a message)
constexpr qsizetype kMostPasted = 16 * 1024 * 1024;

CefRefPtr<CefDictionaryValue> dictionary(const QJsonObject &object) {
    CefRefPtr<CefValue> value = CefParseJSON(QJsonDocument(object).toJson(QJsonDocument::Compact).toStdString(), JSON_PARSER_RFC);
    return value && value->GetType() == VTYPE_DICTIONARY ? value->GetDictionary() : CefDictionaryValue::Create();
}

Qt::CursorShape cursorShape(cef_cursor_type_t type) {
    switch (type) {
    case CT_HAND: return Qt::PointingHandCursor;
    case CT_IBEAM: case CT_VERTICALTEXT: return Qt::IBeamCursor;
    case CT_CROSS: case CT_CELL: return Qt::CrossCursor;
    case CT_WAIT: return Qt::WaitCursor;
    case CT_PROGRESS: return Qt::BusyCursor;
    case CT_HELP: return Qt::WhatsThisCursor;
    case CT_EASTRESIZE: case CT_WESTRESIZE: case CT_EASTWESTRESIZE: case CT_COLUMNRESIZE: return Qt::SizeHorCursor;
    case CT_NORTHRESIZE: case CT_SOUTHRESIZE: case CT_NORTHSOUTHRESIZE: case CT_ROWRESIZE: return Qt::SizeVerCursor;
    case CT_NORTHEASTRESIZE: case CT_SOUTHWESTRESIZE: case CT_NORTHEASTSOUTHWESTRESIZE: return Qt::SizeBDiagCursor;
    case CT_NORTHWESTRESIZE: case CT_SOUTHEASTRESIZE: case CT_NORTHWESTSOUTHEASTRESIZE: return Qt::SizeFDiagCursor;
    case CT_MOVE: case CT_MIDDLEPANNING: return Qt::SizeAllCursor;
    case CT_NOTALLOWED: case CT_NODROP: return Qt::ForbiddenCursor;
    case CT_GRAB: return Qt::OpenHandCursor;
    case CT_GRABBING: return Qt::ClosedHandCursor;
    case CT_NONE: return Qt::BlankCursor;
    default: return Qt::ArrowCursor;
    }
}

// Qt WebEngine's error domain for a Chromium net error (as its web_engine_error.cpp groups them)
int errorDomain(int code) {
    if (code > 0)
        return 7;                           // HttpStatusCodeDomain
    if (code == -105 || code == -137 || (code <= -800 && code > -900))
        return 6;                           // DnsErrorDomain
    if (code <= -100 && code > -200)
        return 2;                           // ConnectionErrorDomain
    if ((code <= -200 && code > -300) || (code <= -700 && code > -800))
        return 3;                           // CertificateErrorDomain
    if (code <= -300 && code > -400)
        return 4;                           // HttpErrorDomain
    if (code <= -600 && code > -700)
        return 5;                           // FtpErrorDomain
    return code ? 1 : 0;                    // InternalErrorDomain, NoErrorDomain
}

// Qt's NavigationType for a CEF transition
int navigationType(cef_transition_type_t type, bool redirect) {
    // a server's redirect or the page's own (a script's location, a meta refresh: a link with the client-redirect flag), as
    // Qt's PageTransitionIsRedirect: "Save password?" lasted only through the form's load, not the site's script after it
    if (redirect || (type & (TT_CLIENT_REDIRECT_FLAG | TT_SERVER_REDIRECT_FLAG)))
        return 6;
    if (type & TT_FORWARD_BACK_FLAG)
        return 3;
    switch (type & TT_SOURCE_MASK) {
    case TT_LINK: return 0;
    case TT_EXPLICIT: case TT_AUTO_BOOKMARK: case TT_KEYWORD: case TT_KEYWORD_GENERATED: return 1;
    case TT_FORM_SUBMIT: return 2;
    case TT_RELOAD: return 4;
    default: return 5;
    }
}

// Qt's DestinationType for where CEF would open a new page
int destination(cef_window_open_disposition_t disposition) {
    switch (disposition) {
    case CEF_WOD_NEW_WINDOW: return 0;
    case CEF_WOD_NEW_POPUP: return 2;
    case CEF_WOD_NEW_BACKGROUND_TAB: return 3;
    default: return 1;
    }
}

// an address only another app may take: not one the engine loads itself
bool ownScheme(const QString &scheme) {
    static const QStringList own{QStringLiteral("http"), QStringLiteral("https"), QStringLiteral("about"), QStringLiteral("data"),
                                 QStringLiteral("blob"), QStringLiteral("file"), QStringLiteral("javascript"), QStringLiteral("browser"),
                                 QStringLiteral("chrome"), QStringLiteral("chrome-error"), QStringLiteral("filesystem")};
    return own.contains(scheme.toLower());
}

// Qt's drop actions and CEF's drag operations
cef_drag_operations_mask_t operations(Qt::DropActions actions) {
    uint32_t ops = DRAG_OPERATION_NONE;
    if (actions & Qt::CopyAction)
        ops |= DRAG_OPERATION_COPY;
    if (actions & Qt::MoveAction)
        ops |= DRAG_OPERATION_MOVE;
    if (actions & Qt::LinkAction)
        ops |= DRAG_OPERATION_LINK;
    return cef_drag_operations_mask_t(ops);
}
Qt::DropAction action(int op) {
    return op & DRAG_OPERATION_MOVE ? Qt::MoveAction : op & DRAG_OPERATION_COPY ? Qt::CopyAction
         : op & DRAG_OPERATION_LINK ? Qt::LinkAction : Qt::IgnoreAction;
}
Qt::DropActions actions(int ops) {
    Qt::DropActions a;
    if (ops & DRAG_OPERATION_COPY)
        a |= Qt::CopyAction;
    if (ops & DRAG_OPERATION_MOVE)
        a |= Qt::MoveAction;
    if (ops & DRAG_OPERATION_LINK)
        a |= Qt::LinkAction;
    return a;
}

// what another app's drag carries, as the page takes it: local files, a link, text and HTML
CefRefPtr<CefDragData> dragData(const QMimeData *mime) {
    CefRefPtr<CefDragData> data = CefDragData::Create();
    bool link = false;
    for (const QUrl &url : mime->urls()) {
        if (url.isLocalFile())
            data->AddFile(url.toLocalFile().toStdString(), url.fileName().toStdString());
        else if (!link) {
            data->SetLinkURL(url.toString().toStdString());
            link = true;
        }
    }
    if (mime->hasText())
        data->SetFragmentText(mime->text().toStdString());
    if (mime->hasHtml())
        data->SetFragmentHtml(mime->html().toStdString());
    return data;
}

// what a drag out of the page carries, for other apps: a link, text, HTML, the page's files
QMimeData *mimeData(CefRefPtr<CefDragData> data) {
    auto *mime = new QMimeData;
    QList<QUrl> urls;
    if (data->IsLink() && !data->GetLinkURL().empty())
        urls.append(QUrl(QString::fromStdString(data->GetLinkURL().ToString())));
    std::vector<CefString> paths;
    if (data->GetFilePaths(paths))
        for (const CefString &path : paths)
            urls.append(QUrl::fromLocalFile(QString::fromStdString(path.ToString())));
    if (!urls.isEmpty())
        mime->setUrls(urls);
    const QString text = QString::fromStdString(data->GetFragmentText().ToString());
    if (!text.isEmpty())
        mime->setText(text);
    else if (data->IsLink())
        mime->setText(QString::fromStdString(data->GetLinkURL().ToString()));
    const QString html = QString::fromStdString(data->GetFragmentHtml().ToString());
    if (!html.isEmpty())
        mime->setHtml(html);
    return mime;
}

// a script as the page will run it: at document creation, DOM ready or load, in every frame or the top one only
struct ScriptSpec {
    QString key;
    std::string source;
    bool opsisWorld = false;
};
ScriptSpec spec(const QVariantMap &s) {
    QString source = s.value(QStringLiteral("sourceCode")).toString();
    if (!s.value(QStringLiteral("runsOnSubFrames")).toBool())
        source = QStringLiteral("if (self === top) {\n") + source + QStringLiteral("\n}");
    const int point = s.value(QStringLiteral("injectionPoint")).toInt();
    if (point == 1)
        source = QStringLiteral("(() => { const run = () => {\n") + source
            + QStringLiteral("\n}; if (document.readyState === 'loading') addEventListener('DOMContentLoaded', run); else run(); })();");
    else if (point == 0)
        source = QStringLiteral("(() => { const run = () => {\n") + source
            + QStringLiteral("\n}; if (document.readyState !== 'complete') addEventListener('load', run); else run(); })();");
    ScriptSpec out;
    out.opsisWorld = s.value(QStringLiteral("worldId")).toInt() != 0;
    out.source = source.toStdString();
    out.key = s.value(QStringLiteral("name")).toString() + u':' + QString::fromLatin1(QCryptographicHash::hash(source.toUtf8(), QCryptographicHash::Sha1).toHex())
        + (out.opsisWorld ? u":opsis" : u":page");
    return out;
}
// the scripts a page on `profile` runs, its profile's then its own
QList<ScriptSpec> specsOf(QObject *profile, ScriptCollection *own) {
    QList<ScriptSpec> specs;
    if (auto *scripts = profile ? qobject_cast<ScriptCollection *>(profile->property("userScripts").value<QObject *>()) : nullptr)
        for (const QVariant &s : scripts->collection())
            specs.append(spec(s.toMap()));
    for (const QVariant &s : own->collection())
        specs.append(spec(s.toMap()));
    if (noScripts)
        specs.clear();
    return specs;
}
bool sameScripts(const QList<ScriptSpec> &a, const QList<ScriptSpec> &b) {
    if (a.size() != b.size())
        return false;
    for (qsizetype i = 0; i < a.size(); ++i)
        if (a[i].key != b[i].key)   // a key holds its source's hash and its world
            return false;
    return true;
}
// the native route's scripts as browser-page takes them (CreateBrowser's extra info, the "opsis.scripts" message):
// Opsis's world script first, then the page's
CefRefPtr<CefDictionaryValue> scriptsInfo(const QList<ScriptSpec> &specs, int generation) {
    CefRefPtr<CefListValue> list = CefListValue::Create();
    const auto add = [&list](const std::string &key, const std::string &source, bool opsis) {
        CefRefPtr<CefDictionaryValue> s = CefDictionaryValue::Create();
        s->SetString("key", key);
        s->SetString("source", source);
        s->SetBool("opsis", opsis);
        list->SetDictionary(list->GetSize(), s);
    };
    add("opsis-world", kWorldScript, true);
    add("thyris-clipboard", kClipboardScript, true);
    add("thyris-clipboard-page", kClipboardPageScript, false);
    add("thyris-store", kStoreScript, true);
    add("thyris-store-page", kStorePageScript, false);
    for (const ScriptSpec &s : specs)
        add(s.key.toStdString(), s.source, s.opsisWorld);
    CefRefPtr<CefDictionaryValue> info = CefDictionaryValue::Create();
    info->SetInt("generation", generation);
    info->SetList("scripts", list);
    return info;
}
}

// CEF's side of a page: its callbacks come on CEF's UI thread and go on to the item on the GUI thread, while it is
// there. It outlives the item until CEF has closed the page.
// A request the profile's filter refused. It fails as Chrome and Qt WebEngine fail a blocked request
// (net::ERR_BLOCKED_BY_CLIENT); RV_CANCEL in OnBeforeResourceLoad made it read as an aborted load (ERR_ABORTED).
class RefusedRequest : public CefResourceRequestHandler, public CefResourceHandler {
public:
    CefRefPtr<CefResourceHandler> GetResourceHandler(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override {
        return this;
    }
    bool Open(CefRefPtr<CefRequest>, bool &handle, CefRefPtr<CefCallback>) override {
        handle = true;
        return true;
    }
    void GetResponseHeaders(CefRefPtr<CefResponse> response, int64_t &length, CefString &) override {
        response->SetError(ERR_BLOCKED_BY_CLIENT);
        length = 0;
    }
    bool Read(void *, int, int &read, CefRefPtr<CefResourceReadCallback>) override {
        read = 0;
        return false;
    }
    void Cancel() override {}
    IMPLEMENT_REFCOUNTING(RefusedRequest);
};

// A request the filter list answers with a stand-in (its `redirect` resource): the page gets that body, as the response to
// the address it asked for, where Chromium's own redirects refuse data: URLs for most requests
class ServedRequest : public CefResourceRequestHandler, public CefResourceHandler {
public:
    ServedRequest(QByteArray mime, QByteArray body) : m_mime(std::move(mime)), m_body(std::move(body)) {}
    CefRefPtr<CefResourceHandler> GetResourceHandler(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override {
        return this;
    }
    bool Open(CefRefPtr<CefRequest>, bool &handle, CefRefPtr<CefCallback>) override {
        handle = true;
        return true;
    }
    void GetResponseHeaders(CefRefPtr<CefResponse> response, int64_t &length, CefString &) override {
        response->SetStatus(200);
        response->SetStatusText("OK");
        response->SetMimeType(m_mime.toStdString());
        // a script or fetch asked for with CORS still gets it
        response->SetHeaderByName("Access-Control-Allow-Origin", "*", true);
        length = m_body.size();
    }
    bool Read(void *out, int want, int &read, CefRefPtr<CefResourceReadCallback>) override {
        read = int(qMin<qsizetype>(want, m_body.size() - m_offset));
        if (read <= 0) {
            read = 0;
            return false;
        }
        std::memcpy(out, m_body.constData() + m_offset, size_t(read));
        m_offset += read;
        return true;
    }
    void Cancel() override {}

private:
    QByteArray m_mime, m_body;
    qsizetype m_offset = 0;
    IMPLEMENT_REFCOUNTING(ServedRequest);
};

// A request loaded at another address: the filter list's `removeparam` stripped tracking parameters from it
class RewrittenRequest : public CefResourceRequestHandler {
public:
    explicit RewrittenRequest(QUrl url) : m_url(std::move(url)) {}
    ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest> request,
                                     CefRefPtr<CefCallback>) override {
        request->SetURL(m_url.toEncoded().toStdString());
        return RV_CONTINUE;
    }

private:
    QUrl m_url;
    IMPLEMENT_REFCOUNTING(RewrittenRequest);
};

class PageClient : public CefClient, public CefRenderHandler, public CefLifeSpanHandler, public CefLoadHandler,
                   public CefDisplayHandler, public CefDevToolsMessageObserver, public CefKeyboardHandler,
                   public CefFocusHandler, public CefContextMenuHandler, public CefRequestHandler, public CefJSDialogHandler,
                   public CefFindHandler, public CefDialogHandler, public CefDownloadHandler, public CefPermissionHandler {
public:
    PageClient(PageItem *item, std::shared_ptr<PageFrames> frames, std::shared_ptr<PageFrames> popup)
        : m_item(item), m_frames(std::move(frames)), m_popup(std::move(popup)) {}

    // OPSIS_CEF_TRACE: where a page's loads spend their time before Chromium loads anything, on stderr
    void traceStep(const char *what) {
        if (traced)
            std::fprintf(stderr, "cef trace: page %p %s at +%.1f ms\n", static_cast<void *>(this), what, (nowNs() - m_traceT0) / 1e6);
    }

    // GUI thread
    void resize(QSize size, qreal scale, QPoint origin) {
        CefRefPtr<CefBrowser> browser;
        bool rescaled;
        {
            QMutexLocker lock(&m_lock);
            m_size = size;
            rescaled = m_scale != scale;
            m_scale = scale;
            m_origin = origin;
            browser = m_browser;
        }
        if (!browser)
            return;
        // a new scale is new screen info: without it the engine kept drawing at the old scale (GetScreenInfo)
        if (traced)
            std::fprintf(stderr, "cef trace: page resized to %dx%d at scale %.2f%s\n", size.width(), size.height(), scale,
                         rescaled ? " (new screen info)" : "");
        if (rescaled)
            browser->GetHost()->NotifyScreenInfoChanged();
        browser->GetHost()->WasResized();
    }
    // DevTools (PageItem::setDevToolsView, DevToolsBridge): the relay's messages into the page's DevTools session, and
    // what comes back that is the front end's (answers past DevToolsBridge::frontEnd, every event) out to it
    void sendDevTools(const QByteArray &message) {
        CefRefPtr<PageClient> self(this);
        CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<PageClient> c, QByteArray m) {
            if (CefRefPtr<CefBrowser> page = c->browser())
                page->GetHost()->SendDevToolsMessage(m.constData(), size_t(m.size()));
        }, self, message));
    }
    void tapDevTools(bool on) {
        CefRefPtr<PageClient> self(this);
        CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<PageClient> c, bool on) {
            CefRefPtr<CefBrowser> page = c->browser();
            c->m_tap = on && page ? page->GetHost()->AddDevToolsMessageObserver(new DevToolsTap(c)) : nullptr;
        }, self, on));
    }
    class DevToolsTap : public CefDevToolsMessageObserver {
    public:
        explicit DevToolsTap(CefRefPtr<PageClient> client) : m_client(client) {}
        bool OnDevToolsMessage(CefRefPtr<CefBrowser>, const void *data, size_t size) override {
            const qint64 id = DevToolsBridge::leadingId(static_cast<const char *>(data), qsizetype(size));
            if (id >= 0 && id < DevToolsBridge::frontEnd)
                return false;       // Thyris's own call's answer
            const QByteArray message(static_cast<const char *>(data), qsizetype(size));
            m_client->toItem([message, id](PageItem *item) { item->fromDevTools(message, id); });
            return id >= 0;
        }
        void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int, bool, const void *, size_t) override {}
        void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString &, const void *, size_t) override {}
    private:
        CefRefPtr<PageClient> m_client;
        IMPLEMENT_REFCOUNTING(DevToolsTap);
    };
    // a DevTools method of the checks' own (PageItem::devtoolsCall), on CEF's UI thread
    void devtoolsCall(const QString &method, const QJsonObject &params) {
        CefRefPtr<PageClient> self(this);
        CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<PageClient> c, QString m, QJsonObject p) { c->devtools(m, p); }, self, method, params));
    }
    void load(const QUrl &url) {
        if (traced)
            std::fprintf(stderr, "cef trace: page %p load of %s asked at +%.1f ms\n", static_cast<void *>(this), qPrintable(url.host()),
                         (nowNs() - m_traceT0) / 1e6);
        QMutexLocker lock(&m_lock);
        // a failed load leaves no entry, as in Qt WebEngine (Opsis draws its own failure pages): a load from Chromium's
        // error page takes its entry (the engine's navigation patch, ~/dev/tacit-web/cef-tacit-navigation.patch)
        const std::string address = (m_onErrorEntry && tacitEngine ? "opsis-replace:" : "") + url.toString().toStdString();
        if (m_browser && !m_firstLoad)
            m_browser->GetMainFrame()->LoadURL(address);
        else
            m_pending = url;
    }
    void hide(bool hidden) {
        QMutexLocker lock(&m_lock);
        m_hidden = hidden;
        if (m_browser)
            m_browser->GetHost()->WasHidden(hidden);
    }
    CefRefPtr<CefBrowser> browser() {
        QMutexLocker lock(&m_lock);
        return m_browser;
    }
    // a number for a DevTools call: they must go up
    int nextCall() { return ++m_nextCall; }
    // Runtime.evaluate over the DevTools protocol, inside this process: no port is open. `call` comes back with the
    // answer (PageItem::answered). World 0 is the page's own; any other is Opsis's.
    void evaluate(int call, const QString &script, int world) {
        CefPostTask(TID_UI, base::BindOnce(&PageClient::evaluateNow, this, call, script.toStdString(), world != 0));
    }
    // a paste from the desktop's clipboard (PageItem::pasteFromDesktop), into the frame with the focus
    void paste(const std::string &script) {
        CefPostTask(TID_UI, base::BindOnce(&PageClient::pasteNow, this, script));
    }
    // the scripts every new document runs (PageItem::syncScripts): added and removed by their keys
    void setScripts(const QList<ScriptSpec> &scripts) {
        CefPostTask(TID_UI, base::BindOnce(&PageClient::setScriptsNow, this, scripts));
    }
    // the native route: the scripts the page starts with, for CreateBrowser or OnBeforePopup (any thread)
    CefRefPtr<CefDictionaryValue> startScripts(const QList<ScriptSpec> &scripts) {
        QMutexLocker lock(&m_lock);
        m_scripts = scripts;
        m_scriptsGeneration = 1;
        return scriptsInfo(m_scripts, m_scriptsGeneration);
    }
    // a new window's view takes this page (PageItem::adopt), on the GUI thread
    void attach(PageItem *item, QSize size, qreal scale, QPoint origin) {
        QMutexLocker lock(&m_lock);
        m_item = item;
        m_size = size;
        m_scale = scale;
        m_origin = origin;
    }
    // the item is going
    // GUI thread. A page with a download still coming stays open, blank and hidden, until the last ends: CEF stops telling
    // a closed page's downloads (CefDownloadManagerDelegateImpl::OnBrowserDestroyed), and the file then came with no word
    // of its progress or its end (a page closed, Opsis's hidden fetcher after a Retry). CefRuntime::stop closes those.
    void close() {
        CefRefPtr<CefBrowser> browser;
        bool keep;
        {
            QMutexLocker lock(&m_lock);
            m_item = nullptr;
            m_closing = true;
            browser = m_browser;
            keep = m_keeping = browser && !m_coming.isEmpty();
        }
        if (!browser)
            return;
        if (!keep) {
            browser->GetHost()->CloseBrowser(true);
            return;
        }
        {
            QMutexLocker lock(&keptLock());
            keptPages().insert(this, this);
        }
        browser->GetHost()->WasHidden(true);
        browser->GetMainFrame()->LoadURL("about:blank");
    }
    // a kept page, closed now (CefRuntime::stop)
    void closeKept() {
        CefRefPtr<CefBrowser> browser;
        {
            QMutexLocker lock(&m_lock);
            browser = m_browser;
        }
        if (browser)
            browser->GetHost()->CloseBrowser(true);
    }
    static QMutex &keptLock() {
        static QMutex lock;
        return lock;
    }
    static QHash<PageClient *, CefRefPtr<PageClient>> &keptPages() {
        static QHash<PageClient *, CefRefPtr<PageClient>> pages;
        return pages;
    }

    // ---- downloads. CEF's UI thread asks; DownloadRequest (requests.h), on the GUI thread, is the profile's
    // downloadRequested's, as Qt WebEngine's. Opsis keeps one per download (the newest of its engine's controls in it).
    static QHash<uint32_t, QPointer<DownloadRequest>> &downloads() {     // GUI thread
        static QHash<uint32_t, QPointer<DownloadRequest>> requests;
        return requests;
    }
    // a download that starts from a load: CEF asks this before it ends the load (ERR_ABORTED), so that end is told as
    // Qt WebEngine's: stopped, isDownload (the page stays)
    bool CanDownload(CefRefPtr<CefBrowser>, const CefString &url, const CefString &) override {
        if (traced)
            std::fprintf(stderr, "cef trace: page %p can download %s?\n", static_cast<void *>(this), url.ToString().c_str());
        if (m_navActive && QUrl(QString::fromStdString(url.ToString())) == m_navUrl)
            m_navDownload = true;
        return true;
    }
    bool OnBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem> item, const CefString &suggested,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override {
        const uint32_t id = item->GetId();
        const QUrl url(QString::fromStdString(item->GetURL().ToString()));
        const QString name = QString::fromStdString(suggested.ToString()), mime = QString::fromStdString(item->GetMimeType().ToString());
        {
            QMutexLocker lock(&m_lock);
            m_coming.insert(id);
        }
        if (traced)
            std::fprintf(stderr, "cef trace: page %p download %u of %s asked\n", static_cast<void *>(this), id, qPrintable(url.toString()));
        CefRefPtr<PageClient> self(this);
        QMetaObject::invokeMethod(qApp, [self, id, url, name, mime, callback] { self->downloadAsked(id, url, name, mime, callback); },
                                  Qt::QueuedConnection);
        return true;
    }
    // GUI thread: the profile's handler takes it (accept()) or leaves it, and it does not start
    void downloadAsked(uint32_t id, const QUrl &url, const QString &name, const QString &mime, CefRefPtr<CefBeforeDownloadCallback> callback) {
        // Chromium places a download again when it resumes: one Opsis has goes on where it is
        if (QPointer<DownloadRequest> known = downloads().value(id); known && known->accepted()) {
            callback->Continue(known->partPath().toStdString(), false);
            return;
        }
        PageItem *item;
        {
            QMutexLocker lock(&m_lock);
            item = m_item;
        }
        QObject *profile = item ? item->profile() : nullptr;
        if (!profile) {
            downloadEnded(id);
            return;         // the callback goes unanswered: CEF cancels it
        }
        auto *request = new DownloadRequest(item, profile);
        request->url = url;
        request->suggestedFileName = name;
        request->mimeType = mime;
        const QString folder = profile->property("downloadPath").toString();
        request->setDownloadDirectory(!folder.isEmpty() ? folder : QStandardPaths::writableLocation(QStandardPaths::DownloadLocation));
        request->start = [callback](const QString &path) { callback->Continue(path.toStdString(), false); };
        CefRefPtr<PageClient> self(this);
        request->released = [self, id] { self->downloadEnded(id); };
        downloads().insert(id, request);
        QMetaObject::invokeMethod(profile, "downloadRequested", Q_ARG(QVariant, QVariant::fromValue<QObject *>(request)));
        if (!request->accepted()) {
            downloads().remove(id);
            request->start = nullptr;       // CEF cancels it
            request->deleteLater();
        }
    }
    void OnDownloadUpdated(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) override {
        DownloadRequest::Update u;
        u.total = item->GetTotalBytes();
        u.received = item->GetReceivedBytes();
        u.inProgress = item->IsInProgress();
        u.complete = item->IsComplete();
        u.canceled = item->IsCanceled();
        u.interrupted = item->IsInterrupted();
        u.paused = item->IsPaused();
        u.reason = int(item->GetInterruptReason());
        const uint32_t id = item->GetId();
        if (traced)
            std::fprintf(stderr, "cef trace: page %p download %u %s: %lld of %lld%s%s%s reason %d\n", static_cast<void *>(this), id,
                         item->GetURL().ToString().c_str(), (long long)u.received, (long long)u.total, u.complete ? " complete" : "",
                         u.canceled ? " canceled" : "", u.interrupted ? " interrupted" : "", u.reason);
        if (u.complete || u.canceled)
            downloadEnded(id);
        QMetaObject::invokeMethod(qApp, [id, u, callback] {
            QPointer<DownloadRequest> request = downloads().value(id);
            if (!request)
                return;
            request->engine = [callback](DownloadRequest::Control c) {
                switch (c) {
                case DownloadRequest::Cancel: callback->Cancel(); break;
                case DownloadRequest::Pause: callback->Pause(); break;
                case DownloadRequest::Resume: callback->Resume(); break;
                }
            };
            request->update(u);
            if (request && request->isFinished())
                downloads().remove(id);
        }, Qt::QueuedConnection);
    }
    // any thread: a download of this page's is over for it; a kept page with none left closes
    void downloadEnded(uint32_t id) {
        CefRefPtr<CefBrowser> browser;
        {
            QMutexLocker lock(&m_lock);
            if (!m_coming.remove(id) || !m_keeping || !m_coming.isEmpty())
                return;
            browser = m_browser;
        }
        if (browser)
            browser->GetHost()->CloseBrowser(true);
    }

    CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
    CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }

    // GUI thread: the profile's request filter (the ad blocker), or none
    void setFilter(RequestFilterRef filter) {
        QMutexLocker lock(&m_lock);
        m_filter = std::move(filter);
    }
    void giveHtml(const QUrl &url, const QByteArray &html) {
        QMutexLocker lock(&m_lock);
        m_givenUrl = url;
        m_givenHtml = html.isNull() ? QByteArray("") : html;
    }

    // ---- requests (IO thread): each one the page makes goes past the profile's filter, as Qt WebEngine's interceptor.
    // Decided here, CEF's first look at the request: an allowed one gets no handler and so none of CEF's interception
    // after it (before-load, response, completion), where answering every request in OnBeforeResourceLoad kept each one,
    // a video's segments too, in that path (2026-10-08).
    CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                                                                   CefRefPtr<CefRequest> request, bool, bool,
                                                                   const CefString &, bool &) override {
        RequestFilterRef filter;
        QByteArray given;
        const QUrl url(QString::fromStdString(request->GetURL().ToString()));
        const cef_resource_type_t type = request->GetResourceType();
        {
            QMutexLocker lock(&m_lock);
            filter = m_filter;
            // loadHtml's page: its document from the string, at its address (no request leaves for it)
            if (type == RT_MAIN_FRAME && !m_givenHtml.isNull() && url == m_givenUrl)
                given = std::exchange(m_givenHtml, QByteArray());
        }
        if (!given.isNull())
            return new ServedRequest(QByteArrayLiteral("text/html"), given);
        if (!filter)
            return nullptr;
        // the top document's address, as Qt's firstPartyUrl: the request's own for a main-frame load
        QUrl page = url;
        if (type != RT_MAIN_FRAME && type != RT_NAVIGATION_PRELOAD_MAIN_FRAME) {
            CefRefPtr<CefFrame> main = browser ? browser->GetMainFrame() : nullptr;
            page = main ? QUrl(QString::fromStdString(main->GetURL().ToString())) : QUrl();
        }
        const RequestDecision decision = filter->decide(url, page, kind(type));
        switch (decision.action) {
        case RequestDecision::Block:
            return new RefusedRequest;
        case RequestDecision::Serve:
            return new ServedRequest(decision.mime, decision.body);
        case RequestDecision::Load:
            return new RewrittenRequest(decision.url);
        case RequestDecision::Allow:
            break;
        }
        return nullptr;
    }
    // a request's type as uBlock Origin's lists name it (Qt's interceptor maps its own the same way, src/adblock.cpp)
    static const char *kind(cef_resource_type_t type) {
        switch (type) {
        case RT_MAIN_FRAME:
        case RT_NAVIGATION_PRELOAD_MAIN_FRAME: return "main_frame";
        case RT_SUB_FRAME:
        case RT_NAVIGATION_PRELOAD_SUB_FRAME: return "sub_frame";
        case RT_STYLESHEET: return "stylesheet";
        case RT_SCRIPT:
        case RT_WORKER:
        case RT_SHARED_WORKER:
        case RT_SERVICE_WORKER: return "script";
        case RT_IMAGE:
        case RT_FAVICON: return "image";
        case RT_FONT_RESOURCE: return "font";
        case RT_OBJECT:
        case RT_PLUGIN_RESOURCE: return "object";
        case RT_MEDIA: return "media";
        case RT_XHR: return "xmlhttprequest";
        case RT_PING: return "ping";
        case RT_CSP_REPORT: return "csp_report";
        default: return "other";
        }
    }

    // ---- navigations and new windows (CEF's UI thread; the QML handler runs while the page waits)
    bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool, bool redirect) override {
        const QUrl url(QString::fromStdString(request->GetURL().ToString()));
        const bool main = frame->IsMain();
        if (!main && ownScheme(url.scheme()))
            return false;
        if (main)
            m_mainTarget = url;
        bool rejected = false;
        const int type = navigationType(request->GetTransitionType(), redirect);
        const bool form = request->GetPostData() != nullptr;
        const qint64 asked = traced ? nowNs() : 0;
        toItemNow([&](PageItem *item) {
            NavigationRequest r;
            r.url = url;
            r.isMainFrame = main;
            r.navigationType = type;
            r.hasFormData = form;
            emit item->navigationRequested(&r);
            rejected = r.rejected;
        });
        // the empty document CEF makes the page with (PageItem::create) is no load of the page's, as in Qt WebEngine,
        // which has none: reported, it ended "loaded" and BrowserView took the page for drawn before its site answered
        const bool creation = main && !m_navigated && url == QUrl(QStringLiteral("about:blank"));
        if (main)
            m_navigated = true;
        // the load starts after its request, as in Qt WebEngine: Opsis reads the request's type when the load starts
        // (BrowserView's newLoad keeps "Save password?" through a form's load); a refused one starts and ends too
        if (main && !redirect && !creation)
            startLoad(url);
        if (traced && main) {
            m_traceNav = nowNs();
            std::fprintf(stderr, "cef trace: page %p navigation to %s (transition 0x%x, Qt type %d)%s held %.1f ms on Opsis's thread, at +%.1f ms\n",
                         static_cast<void *>(this), qPrintable(url.host() + url.path()), unsigned(request->GetTransitionType()), type,
                         rejected ? " refused," : "", (m_traceNav - asked) / 1e6, (m_traceNav - m_traceT0) / 1e6);
        }
        return rejected;    // a refused main-frame load ends in OnLoadError, ERR_ABORTED
    }
    bool OnOpenURLFromTab(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &targetUrl,
                          CefRequestHandler::WindowOpenDisposition disposition, bool gesture) override {
        if (disposition == CEF_WOD_CURRENT_TAB)
            return false;
        const QUrl url(QString::fromStdString(targetUrl.ToString()));
        toItemNow([&](PageItem *item) {
            NewWindowRequest r;
            r.requestedUrl = url;
            r.destination = destination(disposition);
            r.userInitiated = gesture;
            emit item->newWindowRequested(&r);
            if (r.target)
                r.target->setUrl(url);
        });
        return true;
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString &targetUrl, const CefString &,
                       CefLifeSpanHandler::WindowOpenDisposition disposition, bool gesture, const CefPopupFeatures &features, CefWindowInfo &info,
                       CefRefPtr<CefClient> &client, CefBrowserSettings &settings, CefRefPtr<CefDictionaryValue> &scripts,
                       bool *) override {
        const QUrl url(QString::fromStdString(targetUrl.ToString()));
        CefRefPtr<PageClient> made;
        bool shared = false;
        QList<ScriptSpec> specs;
        toItemNow([&](PageItem *item) {
            NewWindowRequest r;
            r.requestedUrl = url;
            r.destination = destination(disposition);
            r.userInitiated = gesture;
            r.requestedGeometry = QRect(features.xSet ? features.x : 0, features.ySet ? features.y : 0,
                                        features.widthSet ? features.width : 0, features.heightSet ? features.height : 0);
            emit item->newWindowRequested(&r);
            if (r.target) {
                made = r.target->adopt();
                shared = r.target->shared();
                specs = specsOf(r.target->profile(), r.target->userScripts());
            }
        });
        if (!made)
            return true;    // not opened: nothing opens
        // the native route: its first document is the opener's to make, with these in
        if (nativeRoute)
            scripts = made->startScripts(specs);
        info.SetAsWindowless(0);
        info.shared_texture_enabled = shared;
        info.external_begin_frame_enabled = !ownBeat;
        settings.windowless_frame_rate = 120;      // as openNow's: twice a 60 Hz screen's rate
        settings.background_color = CefColorSetARGB(255, 255, 255, 255);
        client = made;
        return false;
    }
    bool DoClose(CefRefPtr<CefBrowser>) override {
        if (m_closing)
            return false;
        // the page called window.close(): Opsis decides, and closes the view (close()) if it agrees
        toItem([](PageItem *item) { emit item->windowCloseRequested(); });
        return true;
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        traceStep("made");
        bool gone, hidden;
        QUrl pending;
        {
            QMutexLocker lock(&m_lock);
            m_browser = browser;
            gone = !m_item;
            hidden = m_hidden;
            pending = m_pending;
            if (m_errorPagesOff)
                errorPagesCall(browser->GetIdentifier(), false);
        }
        // not under the lock: on this thread CEF may call straight back (GetViewRect, OnBeforeClose)
        if (gone) {         // closed while CEF was making it
            browser->GetHost()->CloseBrowser(true);
            return;
        }
        // the item may have taken the keys before the page was made (focusInEvent found no page then): the page's own
        // focus follows, or a field the page focuses as it loads fires no focus event (the password Fill row's watcher)
        toItem([browser](PageItem *item) {
            item->noteBrowser(browser->GetIdentifier());
            if (traced)
                std::fprintf(stderr, "cef trace: page %p made, %s the keys\n", static_cast<void *>(item),
                             item->hasActiveFocus() ? "with" : "without");
            if (item->hasActiveFocus())
                browser->GetHost()->SetFocus(true);
        });
        if (noDevtools || nativeRoute) {
            // the native route's scripts came with the page (startScripts); syncScripts sends any changed since
            loadPending();
            if (nativeRoute)
                toItem([](PageItem *item) { item->syncScripts(); });
            if (hidden)
                browser->GetHost()->WasHidden(true);
            return;
        }
        m_devtools = browser->GetHost()->AddDevToolsMessageObserver(this);
        // Opsis's world in every document, and the way back from it
        // the Page domain runs a new document's scripts only while it is enabled
        if (!noPageDomain)
            devtools(QStringLiteral("Page.enable"), {});
        if (!noRuntimeDomain)
            devtools(QStringLiteral("Runtime.enable"), {});
        devtools(QStringLiteral("Runtime.addBinding"), {{QStringLiteral("name"), QStringLiteral("__opsis")}, {QStringLiteral("executionContextName"), QStringLiteral("opsis")}});
        devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"),
                 {{QStringLiteral("source"), QString::fromLatin1(kWorldScript)}, {QStringLiteral("worldName"), QStringLiteral("opsis")}, {QStringLiteral("runImmediately"), true}});
        devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"),
                 {{QStringLiteral("source"), QString::fromLatin1(kClipboardScript)}, {QStringLiteral("worldName"), QStringLiteral("opsis")}, {QStringLiteral("runImmediately"), true}});
        devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"),
                 {{QStringLiteral("source"), QString::fromLatin1(kClipboardPageScript)}, {QStringLiteral("runImmediately"), true}});
        devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"),
                 {{QStringLiteral("source"), QString::fromLatin1(kStoreScript)}, {QStringLiteral("worldName"), QStringLiteral("opsis")}, {QStringLiteral("runImmediately"), true}});
        devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"),
                 {{QStringLiteral("source"), QString::fromLatin1(kStorePageScript)}, {QStringLiteral("runImmediately"), true}});
        // the page's scripts go in before its first document: the item's syncScripts ends in setScriptsNow, which loads
        // the address kept in m_pending once every script is in
        m_firstLoad = true;
        toItem([](PageItem *item) { item->syncScripts(); });
        if (hidden)
            browser->GetHost()->WasHidden(true);
    }
    // A certificate the engine questions (CEF's UI thread): the item's handler holds the load (BrowserView's failure page)
    // and answers. CEF does not say whose load it is: the main frame's when it is the main frame's last target. With no
    // callback the error cannot be let past.
    // A held main-frame load is not held in the engine: CEF lost the page it then let through (its new process asked
    // for its page for 2 s, browser_info_manager.cc "Timeout of new browser info response", and Opsis never heard the
    // page's address or title; 2026-10-09). So it is refused at once, its failure kept from Opsis, which still holds
    // it; Continue loads the address again over Chromium's error page entry (the entry the load was for, a Back's
    // too) with this certificate let through, and Chromium remembers it for the host from then on, as Qt WebEngine.
    bool OnCertificateError(CefRefPtr<CefBrowser>, cef_errorcode_t code, const CefString &requestUrl,
                            CefRefPtr<CefSSLInfo> ssl, CefRefPtr<CefCallback> callback) override {
        const QUrl url(QString::fromStdString(requestUrl.ToString()));
        const bool main = url == m_mainTarget || (url.host() == m_mainTarget.host() && url.port() == m_mainTarget.port());
        QByteArray der;
        if (CefRefPtr<CefX509Certificate> leaf = ssl ? ssl->GetX509Certificate() : nullptr)
            if (CefRefPtr<CefBinaryValue> bytes = leaf->GetDEREncoded()) {
                der.resize(qsizetype(bytes->GetSize()));
                bytes->GetData(der.data(), bytes->GetSize(), 0);
            }
        const QString site = url.host() + QLatin1Char(':') + QString::number(url.port(443));
        {
            QMutexLocker lock(&m_lock);
            if (callback && !der.isEmpty() && m_letThrough.value(site) == der) {
                m_letThrough.remove(site);
                callback->Continue();
                return true;
            }
        }
        CefRefPtr<PageClient> self(this);
        toItem([=](PageItem *item) {
            auto held = std::make_shared<bool>(false);
            auto *error = new CertificateError([self, callback, held, url, site, der, code](bool accept) {
                if (!callback)
                    return;
                if (*held)
                    self->heldAnswered(accept, url, site, der, int(code));
                else if (accept)
                    callback->Continue();
                else
                    callback->Cancel();
            }, item);
            error->url = url;
            error->isMainFrame = main;
            error->type = int(code);
            error->overridable = callback != nullptr;
            error->certificateDer = der;
            emit item->certificateError(error);
            if (!error->deferred && !error->answered()) {
                error->rejectCertificate();
            } else if (!error->answered() && main && callback) {
                *held = true;
                {
                    QMutexLocker lock(&m_lock);
                    m_certHold = 1;
                    m_certContinue.clear();
                }
                callback->Cancel();
            }
        });
        return callback != nullptr;
    }
    // GUI thread: Opsis answered a certificate it holds (OnCertificateError)
    void heldAnswered(bool accept, const QUrl &url, const QString &site, const QByteArray &der, int code) {
        if (!accept) {
            {
                QMutexLocker lock(&m_lock);
                m_certContinue.clear();
            }
            emitLoad(loadInfo(3, url, code));     // Failures.js names the code
            return;
        }
        {
            QMutexLocker lock(&m_lock);
            m_letThrough.insert(site, der);
            if (m_certHold != 0) {      // the error page is not in yet: OnLoadEnd loads it then
                m_certContinue = url;
                return;
            }
        }
        load(url);
    }

    // ---- a page's dialogs (CEF's UI thread): the item's handler shows them (BrowserView's dialog card) and answers;
    // the page waits until then. CEF's dialog types are Qt's numbers (0 alert, 1 confirm, 2 prompt).
    bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString &origin, JSDialogType type, const CefString &message,
                    const CefString &defaultText, CefRefPtr<CefJSDialogCallback> callback, bool &) override {
        dialog(int(type), message, defaultText, origin, callback);
        return true;
    }
    bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString &message, bool,
                              CefRefPtr<CefJSDialogCallback> callback) override {
        dialog(3, message, CefString(), browser->GetMainFrame()->GetURL(), callback);
        return true;
    }
    void dialog(int type, const CefString &message, const CefString &defaultText, const CefString &origin,
                CefRefPtr<CefJSDialogCallback> callback) {
        const QString said = QString::fromStdString(message.ToString()), text = QString::fromStdString(defaultText.ToString());
        const QUrl from(QString::fromStdString(origin.ToString()));
        toItem([=](PageItem *item) {
            auto *request = new DialogRequest([callback](bool ok, const QString &answer) { callback->Continue(ok, answer.toStdString()); }, item);
            request->type = type;
            request->message = said;
            request->defaultText = text;
            request->securityOrigin = from;
            emit item->javaScriptDialogRequested(request);
            if (!request->accepted)
                request->dialogReject();
        });
    }

    // Permissions, as Qt WebEngine asks them (WebEnginePermission's types): the item's handler (BrowserView, Asks.js)
    // answers now or later, from the site's lasting choice or your answer; the page waits until then. Camera and
    // microphone (and the screen) come as a media request, the rest as one prompt that may hold several kinds, which
    // Opsis asks as one only when it knows them all.
    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &origin, uint32_t wanted,
                                        CefRefPtr<CefMediaAccessCallback> callback) override {
        const bool mic = wanted & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE, cam = wanted & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
        const bool screen = wanted & CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE, sound = wanted & CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE;
        const int type = screen ? (sound ? 5 : 4) : mic && cam ? 3 : cam ? 2 : mic ? 1 : 0;
        if (traced)
            fprintf(stderr, "opsis-cef: media ask %u -> %d from %s\n", wanted, type, origin.ToString().c_str());
        if (type == 0)
            return false;
        ask(type, origin, [callback, wanted](bool granted) { granted ? callback->Continue(wanted) : callback->Cancel(); }, 0);
        return true;
    }
    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t prompt, const CefString &origin, uint32_t wanted,
                                CefRefPtr<CefPermissionPromptCallback> callback) override {
        int type = 0;
        switch (wanted) {
        case CEF_PERMISSION_TYPE_NOTIFICATIONS: type = 7; break;
        case CEF_PERMISSION_TYPE_GEOLOCATION: type = 8; break;
        case CEF_PERMISSION_TYPE_CLIPBOARD: type = 9; break;
        case CEF_PERMISSION_TYPE_LOCAL_FONTS: type = 10; break;
        case CEF_PERMISSION_TYPE_POINTER_LOCK: type = 6; break;
        case CEF_PERMISSION_TYPE_MIC_STREAM: type = 1; break;
        case CEF_PERMISSION_TYPE_CAMERA_STREAM: type = 2; break;
        case CEF_PERMISSION_TYPE_MIC_STREAM | CEF_PERMISSION_TYPE_CAMERA_STREAM: type = 3; break;
        default: break;
        }
        if (traced)
            fprintf(stderr, "opsis-cef: permission prompt %llu: %u -> %d from %s\n", (unsigned long long)prompt, wanted, type,
                    origin.ToString().c_str());
        if (type == 0) {
            callback->Continue(CEF_PERMISSION_RESULT_DENY);   // a kind Opsis does not ask about (as Qt WebEngine)
            return true;
        }
        CefRefPtr<PageClient> self(this);
        const std::string from = origin.ToString();
        ask(type, origin, [self, callback, from, wanted](bool granted) {
            callback->Continue(granted ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
            QMutexLocker lock(&self->m_lock);
            self->m_answered.emplace_back(from, wanted);
        }, prompt);
        return true;
    }
    // Chromium keeps a prompt's answer as the site's setting (the notification ask did not come again after Deny and a
    // reload, 2026-10-15). Opsis's answers last for the page load, and its lasting choices it answers itself from the site
    // panel, so the next main-frame load starts without them. Only types Chromium registers: GEOLOCATION_WITH_OPTIONS
    // (its approximate-location feature, off) failed a CHECK when cleared.
    void forgetAnswers(CefRefPtr<CefBrowser> browser) {
        std::vector<std::pair<std::string, uint32_t>> answered;
        {
            QMutexLocker lock(&m_lock);
            answered.swap(m_answered);
        }
        if (answered.empty())
            return;
        static const std::pair<uint32_t, cef_content_setting_types_t> kinds[] = {
            {CEF_PERMISSION_TYPE_NOTIFICATIONS, CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS},
            {CEF_PERMISSION_TYPE_GEOLOCATION, CEF_CONTENT_SETTING_TYPE_GEOLOCATION},
            {CEF_PERMISSION_TYPE_CLIPBOARD, CEF_CONTENT_SETTING_TYPE_CLIPBOARD_READ_WRITE},
            {CEF_PERMISSION_TYPE_LOCAL_FONTS, CEF_CONTENT_SETTING_TYPE_LOCAL_FONTS},
            {CEF_PERMISSION_TYPE_POINTER_LOCK, CEF_CONTENT_SETTING_TYPE_POINTER_LOCK},
            {CEF_PERMISSION_TYPE_MIC_STREAM, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC},
            {CEF_PERMISSION_TYPE_CAMERA_STREAM, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA},
        };
        CefRefPtr<CefRequestContext> context = browser->GetHost()->GetRequestContext();
        for (const auto &[origin, wanted] : answered)
            for (const auto &[permission, setting] : kinds)
                if (wanted & permission)
                    context->SetContentSetting(origin, origin, setting, CEF_CONTENT_SETTING_VALUE_DEFAULT);
    }
    void OnDismissPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t prompt, cef_permission_request_result_t) override {
        toItem([prompt](PageItem *item) {
            if (auto *r = qobject_cast<PermissionRequest *>(item->m_prompts.take(prompt).data()))
                r->drop();
        });
    }
    void ask(int type, const CefString &origin, PermissionRequest::Answer answer, uint64_t prompt) {
        const QUrl from(QString::fromStdString(origin.ToString()));
        toItem([type, from, answer, prompt](PageItem *item) {
            auto *request = new PermissionRequest(answer, item);
            request->origin = from;
            request->permissionType = type;
            if (prompt)
                item->m_prompts.insert(prompt, request);
            if (type == 4 || type == 5)
                emit item->desktopCaptureRequested(request);
            else
                emit item->permissionRequested(request);
        });
    }

    // Qt's errorPageEnabled (the shim's settings; BrowserView turns it off for an https attempt): off, a failed main-frame
    // load commits nothing, so the attempt leaves no history entry (Opsis's CEF build: errorpages-patch.py in
    // book4-edge/cef-pgo; another engine shows its error page as before). The page takes it once it is made.
    static void errorPagesCall(int browser, bool on) {
        static const auto set = reinterpret_cast<void (*)(int, int)>(dlsym(RTLD_DEFAULT, "cef_tacit_error_pages"));
        if (set)
            set(browser, on);
    }
    void setErrorPages(bool on) {
        QMutexLocker lock(&m_lock);
        m_errorPagesOff = !on;
        if (m_browser)
            errorPagesCall(m_browser->GetIdentifier(), on);
    }

    // HTTP sign-in or a proxy's (CEF's IO thread): the item's handler asks in its card and answers; the load waits
    bool GetAuthCredentials(CefRefPtr<CefBrowser>, const CefString &origin, bool isProxy, const CefString &host, int port,
                            const CefString &realm, const CefString &, CefRefPtr<CefAuthCallback> callback) override {
        const QUrl url(QString::fromStdString(origin.ToString()));
        const QString said = QString::fromStdString(realm.ToString());
        const QString proxy = isProxy ? QStringLiteral("%1:%2").arg(QString::fromStdString(host.ToString())).arg(port) : QString();
        if (traced)
            fprintf(stderr, "opsis-cef: sign-in asked by %s (realm %s, proxy %d)\n", origin.ToString().c_str(), realm.ToString().c_str(), isProxy);
        toItem([=](PageItem *item) {
            auto *request = new AuthRequest([callback](bool given, const QString &user, const QString &password) {
                given ? callback->Continue(user.toStdString(), password.toStdString()) : callback->Cancel();
            }, item);
            request->url = url;
            request->realm = said;
            request->proxyHost = proxy;
            request->type = isProxy ? 1 : 0;
            emit item->authenticationDialogRequested(request);
            if (!request->accepted)
                request->dialogReject();
        });
        return true;
    }

    // a file input's pick (CEF's UI thread): the item's handler picks in Files and answers; the page waits until then.
    // CEF's modes are Qt's numbers (0 one, 1 several, 2 folder, 3 save).
    bool OnFileDialog(CefRefPtr<CefBrowser>, FileDialogMode mode, const CefString &, const CefString &defaultPath,
                      const std::vector<CefString> &filters, const std::vector<CefString> &, const std::vector<CefString> &,
                      CefRefPtr<CefFileDialogCallback> callback) override {
        const QString name = QString::fromStdString(defaultPath.ToString());
        QStringList types;
        for (const CefString &f : filters)
            types.append(QString::fromStdString(f.ToString()));
        toItem([=](PageItem *item) {
            auto *request = new FileRequest([callback](const QStringList &paths) {
                if (paths.isEmpty()) {
                    callback->Cancel();
                    return;
                }
                std::vector<CefString> chosen;
                for (const QString &p : paths)
                    chosen.emplace_back(p.toStdString());
                callback->Continue(chosen);
            }, item);
            request->mode = int(mode);
            request->defaultFileName = name;
            request->acceptedMimeTypes = types;
            emit item->fileDialogRequested(request);
            if (!request->accepted)
                request->dialogReject();
        });
        return true;
    }

    // the native route's answers and bridge (browser-page, src/cef/pageprocess.cpp)
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefProcessId,
                                  CefRefPtr<CefProcessMessage> message) override {
        const std::string name = message->GetName().ToString();
        CefRefPtr<CefListValue> arguments = message->GetArgumentList();
        if (!arguments)
            return false;
        if (name == "opsis.evaled") {
            // in the shape of DevTools' Runtime.evaluate result (PageItem::answered); no value is undefined
            const int call = arguments->GetInt(0);
            const bool done = arguments->GetBool(1);
            QByteArray json("{\"result\":{");
            if (arguments->GetType(2) == VTYPE_STRING)
                json += "\"value\":" + QByteArray::fromStdString(arguments->GetString(2).ToString());
            json += "}}";
            toItem([call, done, json](PageItem *item) { item->answered(call, done, json); });
            return true;
        }
        if (name == "opsis.print") {
            toItem([](PageItem *item) { emit item->printRequested(); });
            return true;
        }
        if (name == "opsis.process") {
            // a page process tells its renderer-client-id when it takes the page (its own pid is the sandbox's); the
            // system's pid is the renderer among this browser's descendants with that id
            const qint64 pid = rendererPid(QByteArray::fromStdString(arguments->GetString(0).ToString()));
            if (traced)
                std::fprintf(stderr, "cef trace: page %p process id %s = pid %lld\n", static_cast<void *>(this),
                             arguments->GetString(0).ToString().c_str(), static_cast<long long>(pid));
            if (pid > 0)
                toItem([pid](PageItem *item) {
                    if (item->m_renderPid != pid) {
                        item->m_renderPid = pid;
                        emit item->renderProcessPidChanged();
                    }
                });
            return true;
        }
        if (name == "opsis.bridge") {
            // the main frame's world script reports; a subframe's has only WebChannel messages to send (a login field in
            // a frame)
            const QJsonObject said = QJsonDocument::fromJson(QByteArray::fromStdString(arguments->GetString(0).ToString())).object();
            if (traced)
                std::fprintf(stderr, "cef trace: page %p bridge %s from %s\n", static_cast<void *>(this), qPrintable(said.value(QStringLiteral("k")).toString()),
                             frame && frame->IsMain() ? "main" : "a frame");
            // a copy, from any frame
            if (said.value(QStringLiteral("k")).toString() == QStringLiteral("clip")) {
                toItem([said](PageItem *item) { item->copiedInPage(said); });
                return true;
            }
            if (!frame || !frame->IsMain() && said.value(QStringLiteral("k")).toString() != QStringLiteral("channel"))
                return true;
            if (said.value(QStringLiteral("k")).toString() != QStringLiteral("ctx"))
                toItem([said](PageItem *item) { item->bridged(said); });
            return true;
        }
        return false;
    }
    void OnBeforeClose(CefRefPtr<CefBrowser>) override {
        {
            QMutexLocker lock(&m_lock);
            m_browser = nullptr;
        }
        {
            QMutexLocker lock(&keptLock());
            keptPages().remove(this);
        }
        m_devtools = nullptr;
        CefRuntime::pageClosed();
    }
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int call, bool done, const void *result, size_t size) override {
        const QByteArray json(static_cast<const char *>(result), qsizetype(size));
        const auto purpose = m_purposes.find(call);
        if (purpose == m_purposes.end())
            return;
        const auto [what, key] = purpose->second;
        m_purposes.erase(purpose);
        if (what == QStringLiteral("eval")) {
            const int asked = key.toInt();
            toItem([asked, done, json](PageItem *item) { item->answered(asked, done, json); });
            return;
        }
        const QJsonObject reply = QJsonDocument::fromJson(json).object();
        if (!done)
            qWarning("PageItem: DevTools call %s failed: %s", qPrintable(what), json.constData());
        if (what == QStringLiteral("script")) {
            m_scriptAdding.remove(key);
            if (done)
                m_scriptIds.insert(key, reply.value(QStringLiteral("identifier")).toString().toStdString());
            if (m_scriptAdding.isEmpty())
                loadPending();
        }
        else if (what == QStringLiteral("frames") && done)
            devtools(QStringLiteral("Page.createIsolatedWorld"),
                     {{QStringLiteral("frameId"), reply.value(QStringLiteral("frameTree")).toObject().value(QStringLiteral("frame")).toObject().value(QStringLiteral("id")).toString()}, {QStringLiteral("worldName"), QStringLiteral("opsis")}},
                     QStringLiteral("world"));
        else if (what == QStringLiteral("world")) {
            m_waitAsked = false;
            if (done)
                m_appContext = reply.value(QStringLiteral("executionContextId")).toInt();
            flushWaiting();
        }
    }
    void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString &method, const void *params, size_t size) override {
        const std::string name = method.ToString();
        if (name == "Runtime.executionContextsCleared") {
            m_appContext = 0;
            return;
        }
        if (name != "Runtime.bindingCalled")
            return;
        const QJsonObject event = QJsonDocument::fromJson(QByteArray(static_cast<const char *>(params), qsizetype(size))).object();
        if (qEnvironmentVariableIsSet("OPSIS_CEF_DEBUG"))
            qWarning("PageItem: binding %s", qPrintable(event.value(QStringLiteral("payload")).toString().left(80)));
        if (event.value(QStringLiteral("name")).toString() != QStringLiteral("__opsis"))
            return;
        const QJsonObject message = QJsonDocument::fromJson(event.value(QStringLiteral("payload")).toString().toUtf8()).object();
        if (message.value(QStringLiteral("k")).toString() == QStringLiteral("ctx")) {
            m_appContext = event.value(QStringLiteral("executionContextId")).toInt();
            flushWaiting();
            return;
        }
        toItem([message](PageItem *item) { item->bridged(message); });
    }

    // ---- keys, focus, cursor, menus (CEF's UI thread)
    bool OnKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent &event, CefEventHandle) override {
        if (event.type == KEYEVENT_CHAR)
            return false;
        const int type = event.type, native = event.native_key_code;
        toItem([type, native](PageItem *item) { item->unhandledKey(type, native); });
        return false;
    }
    // Each site's page runs in a renderer of its own, and a new one does not have the focus given to the page before
    // it: the page said document.hasFocus() false, showed no caret in a field and sent no focus events (2026-10-14).
    // CEF hands SetFocus on a moment later and drops it while the page's view is not there yet, so its first frame
    // brings the focus again (refocus).
    void OnRenderViewReady(CefRefPtr<CefBrowser> browser) override {
        m_refocus = true;
        toItem([browser](PageItem *item) {
            if (traced)
                std::fprintf(stderr, "cef trace: page %p renderer ready, %s the keys\n", static_cast<void *>(item),
                             item->hasActiveFocus() ? "with" : "without");
            if (item->hasActiveFocus())
                browser->GetHost()->SetFocus(true);
        });
    }
    void refocus(CefRefPtr<CefBrowser> browser) {
        if (!m_refocus.exchange(false))
            return;
        toItem([browser](PageItem *item) {
            if (item->hasActiveFocus())
                browser->GetHost()->SetFocus(true);
        });
    }
    void OnTakeFocus(CefRefPtr<CefBrowser>, bool next) override {
        toItem([next](PageItem *item) {
            if (QQuickItem *to = item->nextItemInFocusChain(next))
                to->forceActiveFocus(next ? Qt::TabFocusReason : Qt::BacktabFocusReason);
        });
    }
    bool OnCursorChange(CefRefPtr<CefBrowser>, CefCursorHandle, cef_cursor_type_t type, const CefCursorInfo &) override {
        const Qt::CursorShape shape = cursorShape(type);
        toItem([shape](PageItem *item) { item->setCursor(QCursor(shape)); });
        return true;
    }
    void OnStatusMessage(CefRefPtr<CefBrowser>, const CefString &value) override {
        const QUrl link(QString::fromStdString(value.ToString()));
        toItem([link](PageItem *item) { emit item->linkHovered(link); });
    }
    void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override {
        model->Clear();     // no menu of Chromium's: Opsis draws its own, or none
        QVariantMap request{{QStringLiteral("x"), params->GetXCoord()}, {QStringLiteral("y"), params->GetYCoord()},
                            {QStringLiteral("linkUrl"), QUrl(QString::fromStdString(params->GetLinkUrl().ToString()))},
                            {QStringLiteral("selectedText"), QString::fromStdString(params->GetSelectionText().ToString())},
                            {QStringLiteral("mediaUrl"), QUrl(QString::fromStdString(params->GetSourceUrl().ToString()))},
                            {QStringLiteral("mediaType"), int(params->GetMediaType())},
                            {QStringLiteral("isContentEditable"), params->IsEditable()},
                            {QStringLiteral("misspelledWord"), QString::fromStdString(params->GetMisspelledWord().ToString())},
                            {QStringLiteral("spellCheckerSuggestions"), suggestions(params)}};
        toItem([request](PageItem *item) {
            item->m_menuImage = request.value(QStringLiteral("mediaType")).toInt() == CM_MEDIATYPE_IMAGE
                ? request.value(QStringLiteral("mediaUrl")).toUrl() : QUrl();
            item->m_menuPoint = QPointF(request.value(QStringLiteral("x")).toDouble(), request.value(QStringLiteral("y")).toDouble());
            emit item->contextMenuRequested(request);
        });
    }
    bool RunContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams>, CefRefPtr<CefMenuModel>,
                        CefRefPtr<CefRunContextMenuCallback> callback) override {
        callback->Cancel();
        return true;
    }
    // The drag runs on the GUI thread (QDrag::exec waits there until it ends); CEF hears where it ended afterwards.
    bool StartDragging(CefRefPtr<CefBrowser>, CefRefPtr<CefDragData> data, DragOperationsMask allowed, int x, int y) override {
        QMimeData *mime = mimeData(data);
        QImage image;
        QPoint hotspot(x, y);
        if (data->HasImage()) {
            int width = 0, height = 0;
            if (CefRefPtr<CefBinaryValue> png = data->GetImage()->GetAsPNG(1.0f, true, width, height)) {
                QByteArray bytes(qsizetype(png->GetSize()), Qt::Uninitialized);
                png->GetData(bytes.data(), bytes.size(), 0);
                image.loadFromData(bytes, "PNG");
                hotspot = QPoint(data->GetImageHotspot().x, data->GetImageHotspot().y);
            }
        }
        const int ops = int(allowed);
        bool taken = false;
        {
            QMutexLocker lock(&m_lock);
            if (m_item) {
                taken = true;
                QMetaObject::invokeMethod(m_item, [item = m_item, mime, image, hotspot, ops] { item->startDrag(mime, image, hotspot, ops); },
                                          Qt::QueuedConnection);
            }
        }
        if (!taken)
            delete mime;
        return taken;
    }
    void UpdateDragCursor(CefRefPtr<CefBrowser>, DragOperation operation) override {
        const int op = int(operation);
        toItem([op](PageItem *item) { item->dropAnswered(op); });
    }
    bool GetScreenPoint(CefRefPtr<CefBrowser>, int viewX, int viewY, int &screenX, int &screenY) override {
        QMutexLocker lock(&m_lock);
        screenX = m_origin.x() + viewX;
        screenY = m_origin.y() + viewY;
        return true;
    }
    void OnPopupShow(CefRefPtr<CefBrowser>, bool show) override {
        toItem([show](PageItem *item) { item->m_popupShown = show; item->update(); });
    }
    void OnPopupSize(CefRefPtr<CefBrowser>, const CefRect &rect) override {
        const QRectF r(rect.x, rect.y, rect.width, rect.height);
        toItem([r](PageItem *item) { item->m_popupRect = r; item->update(); });
    }
    void OnImeCompositionRangeChanged(CefRefPtr<CefBrowser>, const CefRange &, const RectList &bounds) override {
        if (bounds.empty())
            return;
        const QRectF r(bounds.front().x, bounds.front().y, bounds.front().width, bounds.front().height);
        toItem([r](PageItem *item) { item->m_imeRect = r; });
    }

    void GetViewRect(CefRefPtr<CefBrowser>, CefRect &rect) override {
        QMutexLocker lock(&m_lock);
        rect = CefRect(0, 0, qMax(1, m_size.width()), qMax(1, m_size.height()));
    }
    bool GetScreenInfo(CefRefPtr<CefBrowser>, CefScreenInfo &info) override {
        QMutexLocker lock(&m_lock);
        if (traced)
            std::fprintf(stderr, "cef trace: engine asked for screen info: scale %.2f\n", m_scale);
        info.device_scale_factor = float(m_scale);
        info.rect = info.available_rect = {0, 0, qMax(1, m_size.width()), qMax(1, m_size.height())};
        return true;
    }
    void OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList &, const void *pixels, int width,
                 int height) override {
        (type == PET_VIEW ? m_frames : m_popup)->write(pixels, width, height);
        if (type == PET_VIEW)
            refocus(browser);
        const qint64 painted = traced ? nowNs() : 0;
        const QSize got = type == PET_VIEW ? QSize(width, height) : QSize();
        toItem([painted, got](PageItem *item) { if (!got.isEmpty()) item->m_lastFrame = got; item->frameArrived(); item->busy(); item->update(); if (traced) { item->traceFrame(painted); item->traceResized(got); } });
    }
    void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList &,
                            const CefAcceleratedPaintInfo &info) override {
        (type == PET_VIEW ? m_frames : m_popup)->write(info);
        if (type == PET_VIEW)
            refocus(browser);
        const qint64 painted = traced ? nowNs() : 0;
        const QSize got = type == PET_VIEW ? QSize(info.extra.visible_rect.width, info.extra.visible_rect.height) : QSize();
        toItem([painted, got](PageItem *item) { if (!got.isEmpty()) item->m_lastFrame = got; item->frameArrived(); item->busy(); item->update(); if (traced) { item->traceFrame(painted); item->traceResized(got); } });
    }

    // A main-frame load, as Qt WebEngine reports it: started (status 0) when the navigation starts (OnBeforeBrowse, a
    // refused one too), then failed (3) with Chromium's net error and Qt's domain for it (ERR_ABORTED, -3, for a stop or a
    // refusal), or succeeded (2) once the document has loaded; a document with an HTTP error status succeeds as the site's
    // own page, its status in errorCode with HttpStatusCodeDomain. The error page Chromium commits after a failure reports
    // nothing of its own.
    static QVariantMap loadInfo(int status, const QUrl &url, int code = 0, const QString &text = QString()) {
        QString name = text;
        if (code < 0 && !name.isEmpty() && !name.startsWith(u"net::"))
            name.prepend(QStringLiteral("net::"));
        return {{QStringLiteral("status"), status}, {QStringLiteral("url"), url}, {QStringLiteral("errorCode"), code},
                {QStringLiteral("errorString"), name}, {QStringLiteral("errorDomain"), errorDomain(code)},
                {QStringLiteral("isErrorPage"), false}, {QStringLiteral("isDownload"), false}};
    }
    void emitLoad(const QVariantMap &info) {
        const bool loading = info.value(QStringLiteral("status")).toInt() == 0;
        toItem([loading, info](PageItem *item) {
            item->m_loading = loading;
            if (loading)
                item->m_loadStarted = nowNs();
            emit item->loadingChanged(info);
        });
    }
    // the empty document a new page starts with, heard from after the page's first load has begun (CEF's UI thread)
    bool creationOver(const CefString &address) const {
        return m_navActive && address == "about:blank" && m_navUrl != QUrl(QStringLiteral("about:blank"));
    }
    void startLoad(const QUrl &url) {
        if (m_navActive)        // a load that was replaced ends as stopped
            emitLoad(loadInfo(3, m_navUrl, ERR_ABORTED, QStringLiteral("ERR_ABORTED")));
        m_navActive = true;
        m_navUrl = url;
        m_navDownload = false;
        m_errorPage = false;
        emitLoad(loadInfo(0, url));
    }
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override {
        toItem([back, forward](PageItem *item) {
            if (item->m_canGoBack != back) {
                item->m_canGoBack = back;
                emit item->canGoBackChanged();
            }
            if (item->m_canGoForward != forward) {
                item->m_canGoForward = forward;
                emit item->canGoForwardChanged();
            }
        });
        // a load that ended with no end of its own (about:blank, a javascript: address)
        if (!loading && m_navActive) {
            m_navActive = false;
            emitLoad(loadInfo(2, QUrl(QString::fromStdString(browser->GetMainFrame()->GetURL().ToString()))));
        }
    }
    // The page's process stopped answering (a script that never ends, a hung renderer). Returning true keeps Chromium's own
    // "page unresponsive" prompt away; the page says it itself, and its Wait or Reload comes back through waitForPage and
    // endAndReload. Chromium asks again if the page stays stuck.
    bool OnRenderProcessUnresponsive(CefRefPtr<CefBrowser>, CefRefPtr<CefUnresponsiveProcessCallback> callback) override {
        {
            QMutexLocker lock(&m_lock);
            m_hung = callback;
        }
        toItem([](PageItem *item) { item->setUnresponsive(true); });
        return true;
    }
    void OnRenderProcessResponsive(CefRefPtr<CefBrowser>) override {
        {
            QMutexLocker lock(&m_lock);
            m_hung = nullptr;
        }
        toItem([](PageItem *item) { item->setUnresponsive(false); });
    }
    // Wait: the page gets more time. Both calls go to CEF's UI thread, the thread the callback belongs to.
    void waitForPage() {
        CefRefPtr<CefUnresponsiveProcessCallback> hung;
        {
            QMutexLocker lock(&m_lock);
            hung = std::move(m_hung);
        }
        toItem([](PageItem *item) { item->setUnresponsive(false); });
        if (hung)
            CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefUnresponsiveProcessCallback> c) { c->Wait(); }, hung));
    }
    // Reload: the process ends, and OnRenderProcessTerminated reloads the page once it is gone.
    void endAndReload() {
        CefRefPtr<CefUnresponsiveProcessCallback> hung;
        {
            QMutexLocker lock(&m_lock);
            hung = std::move(m_hung);
            m_reloadOnEnd = hung != nullptr;
        }
        if (hung)
            CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefUnresponsiveProcessCallback> c) { c->Terminate(); }, hung));
    }
    // The page's process ended (a crash, the memory killer, a kill). Chromium keeps the page and makes a new process on
    // the next load; Opsis puts its failure page over the last frame, which otherwise stays on screen and answers nothing.
    void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser, TerminationStatus status, int code, const CefString &) override {
        bool reload;
        {
            QMutexLocker lock(&m_lock);
            reload = std::exchange(m_reloadOnEnd, false);
            m_hung = nullptr;
        }
        toItem([](PageItem *item) { item->setUnresponsive(false); });
        // ended by the page's own Reload: no stopped-process page, the page loads again in a new process
        if (reload) {
            browser->Reload();
            return;
        }
        const int qt = status == TS_PROCESS_WAS_KILLED || status == TS_PROCESS_OOM ? 3 : status == TS_PROCESS_CRASHED ? 2 : 1;
        if (traced)
            std::fprintf(stderr, "cef trace: page %p process ended, status %d, code %d\n", static_cast<void *>(this), int(status), code);
        if (m_navActive) {
            m_navActive = false;
            emitLoad(loadInfo(3, m_navUrl, ERR_ABORTED, QStringLiteral("ERR_ABORTED")));
        }
        toItem([qt, code](PageItem *item) { emit item->renderProcessTerminated(qt, code); });
    }
    void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code, const CefString &text,
                     const CefString &url) override {
        if (!frame->IsMain())
            return;
        const QUrl failed(QString::fromStdString(url.ToString()));
        if (!m_navActive)
            return;
        // the empty document a new page starts with, cut off by its first load: not that load's failure (as OnLoadEnd
        // has it). Ending the load here lost its own end, so the page's first load never said it had loaded (2026-10-14)
        if (code == ERR_ABORTED && failed == QUrl(QStringLiteral("about:blank")) && m_navUrl != failed)
            return;
        {
            QMutexLocker lock(&m_lock);
            if (m_certHold == 1 && code <= -200 && code > -300) {
                m_certHold = 2;
                m_navActive = false;
                m_errorPage = true;
                return;
            }
        }
        m_navActive = false;
        m_errorPage = code != ERR_ABORTED;
        // a load stopped before anything came (a stop, a refusal, a download) commits nothing: the address is the page's
        // own again, as in Qt WebEngine (Chromium's pending address stayed, and Back then went past the page on screen).
        // Only the load under way: one a newer load replaced ends after that one began (a sign-in popup's redirects), and
        // the address is the newer one's.
        if (code == ERR_ABORTED && (failed.isEmpty() || failed == m_navUrl))
            OnAddressChange(nullptr, frame, frame->GetURL());
        if (code == ERR_ABORTED && std::exchange(m_navDownload, false)) {
            QVariantMap info = loadInfo(1, failed.isEmpty() ? m_navUrl : failed);
            info.insert(QStringLiteral("isDownload"), true);
            emitLoad(info);
            return;
        }
        emitLoad(loadInfo(3, failed.isEmpty() ? m_navUrl : failed, code, QString::fromStdString(text.ToString())));
    }
    // the back/forward list, to the item's history.items
    class HistoryVisitor : public CefNavigationEntryVisitor {
    public:
        explicit HistoryVisitor(CefRefPtr<PageClient> client) : m_client(client) {}
        bool Visit(CefRefPtr<CefNavigationEntry> entry, bool current, int index, int total) override {
            m_entries.append({QUrl(QString::fromStdString(entry->GetURL().ToString())), QString::fromStdString(entry->GetTitle().ToString()), index});
            if (current)
                m_current = index;
            if (index == total - 1) {
                for (PageHistoryModel::Entry &e : m_entries)
                    e.offset -= m_current;
                m_client->toItem([entries = m_entries](PageItem *item) { item->history()->items()->setEntries(entries); });
            }
            return true;
        }
    private:
        CefRefPtr<PageClient> m_client;
        QList<PageHistoryModel::Entry> m_entries;
        int m_current = 0;
        IMPLEMENT_REFCOUNTING(HistoryVisitor);
    };
    void listHistory(CefRefPtr<CefBrowser> browser) {
        browser->GetHost()->GetNavigationEntries(new HistoryVisitor(this), false);
    }
    // A main-frame load can bring a new document into a new widget without a new renderer, and CEF's off-screen view
    // does not move the focus over to it: the focus goes again with the next frame (refocus), at the load's start and
    // its end (a field focused as the page loads heard nothing, the password Fill row's watcher, 2026-10-14).
    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType) override {
        if (!frame->IsMain())
            return;
        m_refocus = true;
        forgetAnswers(browser);
    }
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status) override {
        if (!frame->IsMain())
            return;
        m_refocus = true;
        cookiesTouched();       // a load's responses and scripts may have set cookies (SiteData lists them again)
        // the empty document a new page starts with ends after its first load has begun: not that load's end (it ended
        // it, and a certificate's failure that came next belonged to no load, 2026-10-09)
        if (creationOver(frame->GetURL()))
            return;
        if (traced && m_traceNav)
            std::fprintf(stderr, "cef trace: page %p loaded %.1f ms after its navigation started\n", static_cast<void *>(this),
                         (nowNs() - m_traceNav) / 1e6);
        QUrl continued;
        {
            QMutexLocker lock(&m_lock);
            m_onErrorEntry = m_errorPage;
            if (m_errorPage && m_certHold == 2) {
                m_certHold = 0;
                continued = std::exchange(m_certContinue, QUrl());
            }
        }
        listHistory(browser);
        if (m_errorPage) {
            m_errorPage = false;
            if (!continued.isEmpty())
                load(continued);
            return;
        }
        if (!m_navActive)
            return;
        m_navActive = false;
        QVariantMap info = loadInfo(2, QUrl(QString::fromStdString(frame->GetURL().ToString())));
        if (status >= 400) {
            info.insert(QStringLiteral("errorCode"), status);
            info.insert(QStringLiteral("errorDomain"), 7);
        }
        emitLoad(info);
    }
    void OnLoadingProgressChange(CefRefPtr<CefBrowser>, double progress) override {
        // Chromium starts every load at 10 % (its kInitialLoadProgress) before anything has come; Qt WebEngine says 0 until
        // something has, which BrowserView reads as nothing to show yet (the terminal ground stays over the page)
        const int percent = progress <= 0.1 ? 0 : qRound(progress * 100);
        toItem([percent](PageItem *item) {
            if (item->m_progress != percent) {
                item->m_progress = percent;
                emit item->loadProgressChanged();
            }
        });
    }
    void OnFaviconURLChange(CefRefPtr<CefBrowser>, const std::vector<CefString> &addresses) override {
        const QUrl icon = addresses.empty() ? QUrl() : QUrl(QString::fromStdString(addresses.front().ToString()));
        toItem([icon](PageItem *item) {
            if (item->m_icon != icon) {
                item->m_icon = icon;
                emit item->iconChanged();
            }
        });
    }
    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString &address) override {
        if (!frame->IsMain())
            return;
        // a page's source (view-source:, Ctrl+U) has its page's address in the frame: the entry shows which it is, as
        // Qt WebEngine reports it (the card read the page's host, not Source of it)
        if (browser)
            if (CefRefPtr<CefNavigationEntry> entry = browser->GetHost()->GetVisibleNavigationEntry())
                if (const CefString shown = entry->GetDisplayURL(); shown.ToString().rfind("view-source:", 0) == 0 && shown != address)
                    return OnAddressChange(nullptr, frame, shown);
        // nor its address or title once that load has begun: the page read about:blank (and "Blank page") for 15 ms
        // between the address asked and the load's own, and Settings, an own page by its address, went and came back
        // with it, the rail and the window's title flashing (2026-10-15)
        if (creationOver(address))
            return;
        const QUrl url(QString::fromStdString(address.ToString()));
        toItem([url](PageItem *item) {
            if (item->m_url != url) {
                item->m_url = url;
                emit item->urlChanged();
            }
        });
    }
    // the focus went into a text field or editable element, or out (CEF's on-screen keyboard call)
    void OnVirtualKeyboardRequested(CefRefPtr<CefBrowser>, TextInputMode mode) override {
        const bool on = mode != CEF_TEXT_INPUT_MODE_NONE;
        toItem([on](PageItem *item) { item->editableFocused(on); });
    }
    // a find's count, told as it grows; the item hears the last
    void OnFindResult(CefRefPtr<CefBrowser>, int, int count, const CefRect &, int active, bool finalUpdate) override {
        if (finalUpdate)
            toItem([count, active](PageItem *item) { item->found(count, active); });
    }
    // the page went into full screen or out (the Fullscreen API): off-screen, CEF has already sized the page to it;
    // the item's handler keeps it or undoes it (PageItem::fullScreenChanged)
    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool on) override {
        const QUrl origin(QString::fromStdString(browser->GetMainFrame()->GetURL().ToString()));
        toItem([on, origin](PageItem *item) { item->fullScreenChanged(on, origin); });
    }
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &text) override {
        if (creationOver(browser->GetMainFrame()->GetURL()))
            return;
        const QString title = QString::fromStdString(text.ToString());
        toItem([title](PageItem *item) {
            if (item->m_title != title) {
                item->m_title = title;
                emit item->titleChanged();
            }
        });
    }

private:
    // ---- the DevTools bridge (CEF's UI thread)
    // a call of Opsis's own; its answer goes by `purpose` (OnDevToolsMethodResult), or nowhere
    void devtools(const QString &method, const QJsonObject &params, const QString &purpose = QString(), const QString &key = QString()) {
        CefRefPtr<CefBrowser> page = browser();
        if (!page)
            return;
        const int call = nextCall();
        if (!purpose.isEmpty())
            m_purposes.emplace(call, std::make_pair(purpose, key));
        page->GetHost()->ExecuteDevToolsMethod(call, method.toStdString(), dictionary(params));
    }
    // in Opsis's world on the native route, where the page's own scripts cannot change what it uses; call 0 waits for no answer
    void pasteNow(const std::string &script) {
        CefRefPtr<CefBrowser> page = browser();
        CefRefPtr<CefFrame> frame = page ? page->GetFocusedFrame() : nullptr;
        if (!frame && page)
            frame = page->GetMainFrame();
        if (!frame)
            return;
        if (!nativeRoute) {
            frame->ExecuteJavaScript(script, "", 0);
            return;
        }
        CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("opsis.eval");
        message->GetArgumentList()->SetInt(0, 0);
        message->GetArgumentList()->SetString(1, script);
        message->GetArgumentList()->SetBool(2, true);
        frame->SendProcessMessage(PID_RENDERER, message);
    }
    void evaluateNow(int call, const std::string &script, bool opsisWorld) {
        if (nativeRoute) {
            CefRefPtr<CefBrowser> page = browser();
            CefRefPtr<CefFrame> frame = page ? page->GetMainFrame() : nullptr;
            if (!frame) {
                toItem([call](PageItem *item) { item->answered(call, false, QByteArray()); });
                return;
            }
            CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("opsis.eval");
            message->GetArgumentList()->SetInt(0, call);
            message->GetArgumentList()->SetString(1, script);
            message->GetArgumentList()->SetBool(2, opsisWorld);
            frame->SendProcessMessage(PID_RENDERER, message);
            return;
        }
        if (opsisWorld && !m_appContext) {
            // the world is made on demand (the main frame makes its own at each document, this covers before that)
            m_waiting.push_back({call, script});
            if (!m_waitAsked) {
                m_waitAsked = true;
                devtools(QStringLiteral("Page.getFrameTree"), {}, QStringLiteral("frames"));
            }
            return;
        }
        CefRefPtr<CefBrowser> page = browser();
        CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
        params->SetString("expression", script);
        params->SetBool("returnByValue", true);
        if (opsisWorld)
            params->SetInt("contextId", m_appContext);
        // DevTools' message numbers must go up, so the number is given here, not when the call was made
        const int message = nextCall();
        m_purposes.emplace(message, std::make_pair(QStringLiteral("eval"), QString::number(call)));
        if (!page || !page->GetHost()->ExecuteDevToolsMethod(message, "Runtime.evaluate", params)) {
            m_purposes.erase(message);
            toItem([call](PageItem *item) { item->answered(call, false, QByteArray()); });
        }
    }
    void flushWaiting() {
        m_waitAsked = false;
        std::deque<std::pair<int, std::string>> waiting;
        waiting.swap(m_waiting);
        for (const auto &[call, script] : waiting) {
            if (m_appContext)
                evaluateNow(call, script, true);
            else
                toItem([call = call](PageItem *item) { item->answered(call, false, QByteArray()); });
        }
    }
    // the address the page was made for, once its scripts are in (and any given while they went in)
    void loadPending() {
        QUrl url;
        CefRefPtr<CefBrowser> page;
        {
            QMutexLocker lock(&m_lock);
            m_firstLoad = false;
            url = m_pending;
            m_pending = QUrl();
            page = m_browser;
        }
        if (page && url.isValid()) {
            traceStep("scripts in, load asked");
            page->GetMainFrame()->LoadURL(url.toString().toStdString());
        }
    }
    void setScriptsNow(const QList<ScriptSpec> &scripts) {
        if (nativeRoute) {
            int generation;
            {
                QMutexLocker lock(&m_lock);
                if (sameScripts(m_scripts, scripts))
                    return;
                m_scripts = scripts;
                generation = ++m_scriptsGeneration;
            }
            // to every frame's process; the engine keeps the latest for the page's processes to come
            CefRefPtr<CefBrowser> page = browser();
            std::vector<CefString> frames;
            if (page)
                page->GetFrameIdentifiers(frames);
            for (const CefString &id : frames)
                if (CefRefPtr<CefFrame> frame = page->GetFrameByIdentifier(id)) {
                    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("opsis.scripts");
                    message->GetArgumentList()->SetDictionary(0, scriptsInfo(scripts, generation));
                    frame->SendProcessMessage(PID_RENDERER, message);
                }
            return;
        }
        if (noDevtools)
            return;
        QSet<QString> wanted;
        for (const ScriptSpec &s : scripts) {
            wanted.insert(s.key);
            if (m_scriptIds.contains(s.key) || m_scriptAdding.contains(s.key))
                continue;
            m_scriptAdding.insert(s.key);
            QJsonObject params{{QStringLiteral("source"), QString::fromStdString(s.source)}, {QStringLiteral("runImmediately"), true}};
            if (s.opsisWorld)
                params.insert(QStringLiteral("worldName"), QStringLiteral("opsis"));
            devtools(QStringLiteral("Page.addScriptToEvaluateOnNewDocument"), params, QStringLiteral("script"), s.key);
        }
        for (auto it = m_scriptIds.begin(); it != m_scriptIds.end();) {
            if (wanted.contains(it.key())) {
                ++it;
                continue;
            }
            devtools(QStringLiteral("Page.removeScriptToEvaluateOnNewDocument"), {{QStringLiteral("identifier"), QString::fromStdString(it.value())}});
            it = m_scriptIds.erase(it);
        }
        if (m_scriptAdding.isEmpty())
            loadPending();
    }

    // `call(item)` on the GUI thread while this thread waits, unless the item has gone or CEF is stopping (the GUI thread
    // then waits on CEF itself)
    template <typename Call> void toItemNow(Call call) {
        {
            QMutexLocker lock(&m_lock);
            if (!m_item || CefRuntime::stopping())
                return;
        }
        QMetaObject::invokeMethod(qApp, [this, &call] {
            PageItem *item;
            {
                QMutexLocker lock(&m_lock);
                item = m_item;
            }
            if (item)       // on the GUI thread the item cannot go meanwhile
                call(item);
        }, Qt::BlockingQueuedConnection);
    }

    // `call(item)` on the GUI thread, unless the item has gone by then
    template <typename Call> void toItem(Call call) {
        QMutexLocker lock(&m_lock);
        if (m_item)
            QMetaObject::invokeMethod(m_item, [item = m_item, call] { call(item); }, Qt::QueuedConnection);
    }

    QMutex m_lock;
    PageItem *m_item;
    std::vector<std::pair<std::string, uint32_t>> m_answered;  // prompts answered in this page load: origin, kinds (forgetAnswers)
    bool m_errorPagesOff = false;                               // setErrorPages
    bool m_navigated = false;       // a main-frame navigation seen (CEF's UI thread): the first may be the page's creation
    std::shared_ptr<PageFrames> m_frames;
    CefRefPtr<CefBrowser> m_browser;
    RequestFilterRef m_filter;      // the profile's (setFilter), asked on the IO thread
    QUrl m_givenUrl;                // loadHtml: the next main-frame load of this address gets this document
    QByteArray m_givenHtml;
    const qint64 m_traceT0 = traced ? nowNs() : 0;     // OPSIS_CEF_TRACE: the page's client made
    qint64 m_traceNav = 0;
    QUrl m_pending;         // asked for before CEF had made the page, or before its scripts were in
    bool m_firstLoad = false;
    bool m_closing = false; // close() was called: DoClose lets the page go
    CefRefPtr<CefRegistration> m_tap;   // the DevTools relay's observer (tapDevTools), CEF's UI thread
    QSet<uint32_t> m_coming;    // downloads of this page's not over yet (an interrupted one until it is let go)
    bool m_keeping = false;     // closed, and open only for them
    QSize m_size;           // the item's, in its own units
    qreal m_scale = 1;
    bool m_hidden = false;
    QPoint m_origin;        // the item's top left on the screen
    std::shared_ptr<PageFrames> m_popup;
    std::atomic<int> m_nextCall{0};
    std::atomic<bool> m_refocus{false};   // a new renderer is ready: give it the focus again with its first frame
    // CEF's UI thread only
    CefRefPtr<CefRegistration> m_devtools;
    bool m_navActive = false;   // a main-frame load is under way (started, not ended)
    bool m_navDownload = false; // and it turned into a download (CanDownload)
    QUrl m_navUrl;
    QUrl m_mainTarget;          // where the main frame's load last went (redirects too), for OnCertificateError
    bool m_errorPage = false;   // the next main-frame commit is Chromium's error page for a failure already reported
    bool m_onErrorEntry = false;    // the current entry is Chromium's error page (under m_lock): a load replaces it
    // a certificate Opsis holds (OnCertificateError), under m_lock: 1 its load refused in the engine, 2 its error page
    // coming; Continue before that page is in loads it then (m_certContinue); certificates Continue let through, by host:port
    int m_certHold = 0;
    QUrl m_certContinue;
    QHash<QString, QByteArray> m_letThrough;
    std::map<int, std::pair<QString, QString>> m_purposes;   // Opsis's own calls: purpose and key, by call number
    int m_appContext = 0;                                     // Opsis's world in the main frame; 0 until it says
    std::deque<std::pair<int, std::string>> m_waiting;       // evaluations waiting for that world
    bool m_waitAsked = false;
    QHash<QString, std::string> m_scriptIds;                  // scripts in the page: DevTools' identifier by key
    QSet<QString> m_scriptAdding;
    // the native route's scripts and their version, under m_lock
    QList<ScriptSpec> m_scripts;
    int m_scriptsGeneration = 0;

    CefRefPtr<CefUnresponsiveProcessCallback> m_hung;   // the stuck process's callback, under m_lock
    bool m_reloadOnEnd = false;                         // the next end of the page's process is Reload's, under m_lock

    IMPLEMENT_REFCOUNTING(PageClient);
};

namespace {
// The node keeps the frames (and so their textures) until it is gone itself: it can outlive the item by a frame.
class PageNode : public QSGSimpleTextureNode {
public:
    ~PageNode() override {
        for (const Wrapped &w : std::as_const(wrapped))
            delete w.texture;
        delete uploaded;
    }
    struct Wrapped {
        QSGTexture *texture = nullptr;
        QSize size;
    };
    // the newest frame onto this node; false when there is none yet
    bool show(QQuickWindow *window, const PageFrames::Shown &shown) {
        const QSize before = frameSize();
        if (shown.texture) {
            Wrapped &w = wrapped[shown.texture];
            if (w.size != shown.size) {
                delete w.texture;
                w.texture = QNativeInterface::QSGOpenGLTexture::fromNative(shown.texture, window, shown.size);
                w.size = shown.size;
            }
            setTexture(w.texture);
        } else if (!shown.image.isNull()) {
            delete uploaded;
            uploaded = window->createTextureFromImage(shown.image);
            setTexture(uploaded);
        } else if (!uploaded) {
            return false;
        }
        // Qt's setTexture works out the new texture coordinates but marks only the material dirty, so the renderer drew
        // a frame of a new size with the last size's: after a retile the page showed stretched until it next drew,
        // when the pointer came over it (Discord, 2026-10-20; the resize's hold had cropped the old frame to the new box)
        markDirty(frameSize() != before ? QSGNode::DirtyMaterial | QSGNode::DirtyGeometry : QSGNode::DirtyMaterial);
        return true;
    }
    // the shown frame's size in pixels
    QSize frameSize() const { return texture() ? texture()->textureSize() : QSize(); }
    // The frame on `box` at its own size from the top left: a frame of another size (the window is being resized and
    // the engine still sends the old size for a moment) is shown 1:1 and cropped, not stretched (stretched, it smeared
    // the page into strands; Chrome and Qt WebEngine keep it 1:1 too). Within a pixel of the box it fills the box.
    void place(const QRectF &box, qreal dpr) {
        const QSizeF frame = QSizeF(frameSize()) / dpr;
        if (frame.isEmpty() || (qAbs(frame.width() - box.width()) <= 1.5 && qAbs(frame.height() - box.height()) <= 1.5)) {
            setRect(box);
            setSourceRect(QRectF(QPointF(0, 0), QSizeF(frameSize())));
            return;
        }
        const QSizeF shown(qMin(frame.width(), box.width()), qMin(frame.height(), box.height()));
        setRect(QRectF(box.topLeft(), shown));
        setSourceRect(QRectF(0, 0, shown.width() * dpr, shown.height() * dpr));
    }
    std::shared_ptr<PageFrames> frames;
    QHash<GLuint, Wrapped> wrapped;     // the scene graph's handle on each of the three textures, by GL name
    QSGTexture *uploaded = nullptr;     // through memory: the last frame
    PageNode *popup = nullptr;          // the page's own pop-up over it, while shown
};
}

PageItem::PageItem(QQuickItem *parent) : QQuickItem(parent), m_userScripts(new ScriptCollection(this)) {
    setFlag(ItemHasContents);
    setFlag(ItemAcceptsInputMethod);
    setFlag(ItemAcceptsDrops);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    connect(m_userScripts, &ScriptCollection::collectionChanged, this, &PageItem::syncScripts);
    m_beat.setTimerType(Qt::PreciseTimer);
    connect(&m_beat, &QTimer::timeout, this, &PageItem::beatTick);
    m_refresh.setSingleShot(true);
    connect(&m_refresh, &QTimer::timeout, this, &PageItem::refreshFrame);
    m_holdLimit.setSingleShot(true);
    m_holdLimit.setInterval(150);
    connect(&m_holdLimit, &QTimer::timeout, this, &PageItem::endHold);
    static const int types = qRegisterMetaType<NavigationRequest *>() + qRegisterMetaType<NewWindowRequest *>()
        + qRegisterMetaType<DialogRequest *>() + qRegisterMetaType<FullScreenRequest *>()
        + qRegisterMetaType<FileRequest *>() + qRegisterMetaType<CertificateError *>() + qRegisterMetaType<PermissionRequest *>() + qRegisterMetaType<AuthRequest *>()
        + qRegisterMetaType<PageHistory *>() + qRegisterMetaType<PageHistoryModel *>();
    Q_UNUSED(types)
}

PageItem::~PageItem() {
    // the relay first: what it puts off on its way out goes through this page's client
    delete std::exchange(m_bridge, nullptr);
    if (m_client)
        m_client->close();
    qDeleteAll(m_keys);
}

// the request filter a profile carries (Adblock::attach sets it), or none
static RequestFilterRef filterOf(QObject *profile) {
    return profile ? profile->property("requestFilter").value<RequestFilterRef>() : nullptr;
}

void PageItem::setProfile(QObject *profile) {
    if (m_profile == profile)
        return;
    if (auto *old = m_profile ? qobject_cast<ScriptCollection *>(m_profile->property("userScripts").value<QObject *>()) : nullptr)
        disconnect(old, nullptr, this, nullptr);
    m_profile = profile;
    if (auto *scripts = profile ? qobject_cast<ScriptCollection *>(profile->property("userScripts").value<QObject *>()) : nullptr)
        connect(scripts, &ScriptCollection::collectionChanged, this, &PageItem::syncScripts);
    if (m_client)
        m_client->setFilter(filterOf(profile));
    emit profileChanged();
    syncScripts();
}

void PageItem::syncScripts() {
    if (!m_client)
        return;
    const QList<ScriptSpec> specs = specsOf(m_profile, m_userScripts);
    if (qEnvironmentVariableIsSet("OPSIS_CEF_DEBUG"))
        qWarning("PageItem: %lld scripts (profile %p)", qsizetype(specs.size()), static_cast<void *>(m_profile.data()));
    m_client->setScripts(specs);
}

void PageItem::bridged(const QJsonObject &message) {
    const QString kind = message.value(QStringLiteral("k")).toString();
    if (kind == QStringLiteral("channel")) {
        emit webChannelMessage(message.value(QStringLiteral("m")).toString());
        return;
    }
    if (kind == QStringLiteral("storeAdd")) {
        emit storeAddPressed();
        return;
    }
    if (kind != QStringLiteral("scroll"))
        return;
    const QSizeF size(message.value(QStringLiteral("w")).toDouble(), message.value(QStringLiteral("h")).toDouble());
    const QPointF at(message.value(QStringLiteral("x")).toDouble(), message.value(QStringLiteral("y")).toDouble());
    if (m_contentsSize != size) {
        m_contentsSize = size;
        emit contentsSizeChanged();
    }
    if (m_scrollPosition != at) {
        m_scrollPosition = at;
        emit scrollPositionChanged();
    }
    // the page has its new layout: two more frames and the hold is over
    if (m_holding && m_holdFrom < 0)
        m_holdFrom = m_arrived;
}

// ---- input

static CefRefPtr<CefBrowserHost> hostOf(PageClient *client) {
    CefRefPtr<CefBrowser> page = client ? client->browser() : nullptr;
    return page ? page->GetHost() : nullptr;
}

// Hover goes on to the items under the page and to the window's HoverHandlers (Opsis's hover zone, the peek's flick,
// the link label): the page only follows the pointer, it does not take the hover.
void PageItem::hoverMoveEvent(QHoverEvent *event) {
    if (auto host = hostOf(m_client.get()))
        host->SendMouseMoveEvent(Input::mouse(event->position(), event->modifiers(), {}), false);
    busy();
    event->ignore();
}

void PageItem::hoverLeaveEvent(QHoverEvent *event) {
    if (auto host = hostOf(m_client.get()))
        host->SendMouseMoveEvent(Input::mouse(event->position(), event->modifiers(), {}), true);
    event->ignore();
}

void PageItem::click(QMouseEvent *event, bool up, int count) {
    auto host = hostOf(m_client.get());
    if (!host)
        return;
    const cef_mouse_button_type_t button = event->button() == Qt::RightButton ? MBT_RIGHT : event->button() == Qt::MiddleButton ? MBT_MIDDLE : MBT_LEFT;
    if (traced && !up) {
        if (m_traceClick)
            std::fprintf(stderr, "cef trace: click: the page did not redraw\n");
        m_traceClick = nowNs();
        m_traceClickFrame = -1;
    }
    host->SendMouseClickEvent(Input::mouse(event->position(), event->modifiers(), event->buttons()), button, up, count);
    busy();
    event->accept();
}

void PageItem::traceFrame(qint64 painted) {
    if (m_paceLastFrame && painted - m_paceLastFrame < 100'000'000)
        m_paceWorst = qMax(m_paceWorst, painted - m_paceLastFrame);
    m_paceLastFrame = painted;
    if (m_traceClick && m_traceClickFrame < 0) {
        m_traceClickFrame = painted - m_traceClick;
        m_traceClickQueued = nowNs() - painted;
    }
    if (m_traceShow && m_traceShowFrame < 0)
        m_traceShowFrame = painted - m_traceShow;
}

void PageItem::traceSwapped() {
    if (!isVisible())
        return;
    const qint64 now = nowNs();
    const int arrived = m_arrived - m_paceSeen;
    m_paceSeen = m_arrived;
    const bool flowing = now - m_paceLastFrame < 100'000'000;
    if (flowing) {
        if (!m_paceSince)
            m_paceSince = now;
        ++m_paceSwaps;
        m_paceRepeats += arrived == 0;
        m_paceSkipped += qMax(0, arrived - 1);
    }
    if (m_paceSince && (!flowing || now - m_paceSince >= 1'000'000'000)) {
        if (m_paceSwaps >= 10)
            std::fprintf(stderr, "cef trace: pages moving %.1f s: %d window frames, %d repeats, %d skipped, page frames %.1f ms apart at worst; %d scroll steps, %.1f ms apart at worst; touchpad %.0f px, angle %.0f, sent %.0f px\n",
                         (now - m_paceSince) / 1e9, m_paceSwaps, m_paceRepeats, m_paceSkipped, m_paceWorst / 1e6,
                         m_paceWheels, m_paceWheelWorst / 1e6, m_paceSums.x(), m_paceSums.y(), m_paceSent);
        m_paceSince = flowing ? now : 0;
        m_paceSwaps = m_paceRepeats = m_paceSkipped = m_paceWheels = 0;
        m_paceWorst = m_paceWheelWorst = 0;
        m_paceSums = {};
        m_paceSent = 0;
    }
    if (m_traceClick && m_traceClickFrame >= 0) {
        std::fprintf(stderr, "cef trace: click -> page frame %.1f ms (then %.1f ms to Opsis's thread) -> drawn %.1f ms\n",
                     m_traceClickFrame / 1e6, m_traceClickQueued / 1e6, (now - m_traceClick) / 1e6);
        m_traceClick = 0;
    }
    if (m_traceShow) {
        if (!m_traceShowDrawn) {
            std::fprintf(stderr, "cef trace: shown -> drawn %.1f ms (%s)\n", (now - m_traceShow) / 1e6,
                         m_traceShowFrame >= 0 ? "a fresh frame" : "its last picture");
            m_traceShowDrawn = true;
        }
        if (m_traceShowFrame >= 0) {
            std::fprintf(stderr, "cef trace: shown -> fresh page frame %.1f ms -> drawn %.1f ms\n", m_traceShowFrame / 1e6,
                         (now - m_traceShow) / 1e6);
            m_traceShow = 0;
        }
    }
}

void PageItem::mousePressEvent(QMouseEvent *event) {
    forceActiveFocus(Qt::MouseFocusReason);
    // a click focuses the page even when this item had the keys already (no focusInEvent then)
    if (auto host = hostOf(m_client.get()))
        host->SetFocus(true);
    click(event, false, 1);
}

void PageItem::mouseDoubleClickEvent(QMouseEvent *event) {
    click(event, false, 2);
}

void PageItem::mouseMoveEvent(QMouseEvent *event) {
    if (auto host = hostOf(m_client.get()))
        host->SendMouseMoveEvent(Input::mouse(event->position(), event->modifiers(), event->buttons()), false);
    busy();
    event->accept();
}

void PageItem::mouseReleaseEvent(QMouseEvent *event) {
    click(event, true, 1);
}

// OPSIS_CEF_RECORD=<file>: every scroll step that reaches a page, one line each (ns, phase, pixel x y, angle x y), for
// replaying the same hand into the test windows of both engines
static FILE *recording() {
    static FILE *file = [] {
        const QByteArray path = qgetenv("OPSIS_CEF_RECORD");
        return path.isEmpty() ? nullptr : std::fopen(path.constData(), "w");
    }();
    return file;
}

void PageItem::wheelEvent(QWheelEvent *event) {
    if (FILE *file = recording()) {
        std::fprintf(file, "%lld %d %d %d %d %d\n", (long long)nowNs(), int(event->phase()), event->pixelDelta().x(),
                     event->pixelDelta().y(), event->angleDelta().x(), event->angleDelta().y());
        std::fflush(file);
    }
    // the fingers on the touchpad: Glide's steps after they lift are the application's own, and Glide holds the End
    // every Begin starts a gesture: an End that went to another item left the last one down
    if (event->phase() == Qt::ScrollBegin) {
        m_fingersDown = true;
        emit touchpadGesture(true);
    } else if (m_fingersDown && (event->phase() == Qt::ScrollEnd || event->source() == Qt::MouseEventSynthesizedByApplication)) {
        m_fingersDown = false;
        emit touchpadGesture(false);
    }
    // Ctrl and the wheel zooms the page, as in Chrome, where the browser takes it before the page does: a notch a step,
    // a touchpad's smooth steps adding up to one
    if (event->modifiers() & Qt::ControlModifier) {
        m_zoomRest += event->angleDelta().y();
        const qreal notch = QWheelEvent::DefaultDeltasPerStep;
        const int steps = int(m_zoomRest / notch);
        if (steps != 0) {
            m_zoomRest -= steps * notch;
            emit zoomGesture(steps);
        }
        event->accept();
        return;
    }
    m_zoomRest = 0;
    if (auto host = hostOf(m_client.get())) {
        // whole pixels to CEF, the fraction kept for the next step
        m_wheelRest += Input::wheelPixels(event);
        QPoint px(int(m_wheelRest.x()), int(m_wheelRest.y()));
        m_wheelRest -= QPointF(px);
        CefMouseEvent e = Input::mouse(event->position(), event->modifiers(), event->buttons());
        // A touchpad's (and Glide's) pixel deltas are precise: Chromium scrolls by them as they come, where a wheel notch
        // it animates; without the flag each small touchpad step was animated as a notch and scrolling lagged and wobbled
        // (2026-10-07, the owner: "not as smooth as the qt engine one")
        if (!event->pixelDelta().isNull() && !qEnvironmentVariableIsSet("OPSIS_CEF_NOPRECISE"))
            e.modifiers |= EVENTFLAG_PRECISION_SCROLLING_DELTA;
        // Qt's touchpad phase, for Opsis's own CEF build (cef-tacit-wheel-phase.patch reads these bits, which CEF leaves
        // unused; a stock CEF drops them): Chromium then keeps one scroll per gesture, as for Qt WebEngine. The step that
        // begins it must move: Qt's own ScrollBegin comes without movement, and a Began step with none left the whole
        // gesture unscrolled (2026-10-08, the owner's recorded hand on the PA-E engine: the page did not move at all). So
        // ScrollBegin is held back and the first step that moves carries Began; a gesture that never moved sends no end.
        switch (event->phase()) {
        case Qt::ScrollBegin:
            m_wheelBegun = false;
            event->accept();
            return;
        case Qt::ScrollUpdate:
        case Qt::ScrollMomentum:
            if (!m_wheelBegun && px.isNull()) {
                event->accept();
                return;
            }
            e.modifiers |= m_wheelBegun ? 1u << 25 : 1u << 24;
            m_wheelBegun = true;
            if (!px.isNull())
                m_wheelLast = px;
            break;
        case Qt::ScrollEnd:
            if (!m_wheelBegun) {
                event->accept();
                return;
            }
            e.modifiers |= 1u << 26;
            m_wheelBegun = false;
            // CEF drops a wheel step that does not move (CefBrowserHostBase::SendMouseWheelEvent: "Nothing to do"), and an
            // End never does: Chromium never heard a gesture end, kept the first one going all session and scrolled
            // whatever it had first latched onto, so after WhatsApp swapped its chat pane no swipe scrolled anything
            // (2026-10-11, the owner's trace: 154 scroll updates after the switch, no scroller latched). The End carries
            // 1 px the way the gesture went, which CEF lets through. An engine with Opsis's wheel-end patch
            // (cef_tacit_wheel_ends) takes the End as it is.
            static const bool endsPass = dlsym(RTLD_DEFAULT, "cef_tacit_wheel_ends") != nullptr;
            if (px.isNull() && !endsPass)
                px = qAbs(m_wheelLast.y()) >= qAbs(m_wheelLast.x()) ? QPoint(0, m_wheelLast.y() < 0 ? -1 : 1)
                                                                    : QPoint(m_wheelLast.x() < 0 ? -1 : 1, 0);
            break;
        case Qt::NoScrollPhase:
            break;
        }
        if (traced) {
            const qint64 now = nowNs();
            if (m_paceLastWheel && now - m_paceLastWheel < 100'000'000)
                m_paceWheelWorst = qMax(m_paceWheelWorst, now - m_paceLastWheel);
            m_paceLastWheel = now;
            ++m_paceWheels;
            m_paceSums += QPointF(qAbs(event->pixelDelta().y()), qAbs(event->angleDelta().y()));
            m_paceSent += qAbs(px.y());
        }
        host->SendMouseWheelEvent(e, px.x(), px.y());
        busy();
    }
    event->accept();
}

// A touchpad pinch zooms the page in the site's zoom steps (no pinch reached the page at all on CEF, Discord 2026-10-23)
bool PageItem::event(QEvent *event) {
    if (event->type() == QEvent::NativeGesture) {
        auto *g = static_cast<QNativeGestureEvent *>(event);
        if (g->gestureType() == Qt::ZoomNativeGesture) {
            m_pinchRest += g->value();
            // a step every 15 % of the fingers' spread, the rest kept for the next
            while (qAbs(m_pinchRest) >= 0.15) {
                const int step = m_pinchRest > 0 ? 1 : -1;
                m_pinchRest -= step * 0.15;
                emit zoomGesture(step);
            }
        } else if (g->gestureType() == Qt::EndNativeGesture) {
            m_pinchRest = 0;
        }
        event->accept();
        return true;
    }
    return QQuickItem::event(event);
}

// Chromium's key sequence: a raw key down, then the character it types if any (the page sees keydown and keypress), and
// the key up. The event is kept until the page says it left it unhandled (unhandledKey).
void PageItem::keyPressEvent(QKeyEvent *event) {
    // a paste is this window's to give: the engine cannot read the desktop's clipboard (pasteFromDesktop)
    const bool plainPaste = event->key() == Qt::Key_V && event->modifiers() == (Qt::ControlModifier | Qt::ShiftModifier);
    if ((event->matches(QKeySequence::Paste) || plainPaste) && pasteFromDesktop(plainPaste)) {
        event->accept();
        return;
    }
    if (auto host = hostOf(m_client.get())) {
        host->SendKeyEvent(Input::key(event, KEYEVENT_RAWKEYDOWN));
        if (!Input::keyText(event).isEmpty())
            host->SendKeyEvent(Input::key(event, KEYEVENT_CHAR));
        busy();
    }
    m_keys.append(event->clone());
    m_keySent.append(nowNs());
    while (m_keys.size() > 32) {
        delete m_keys.takeFirst();
        m_keySent.removeFirst();
    }
    event->accept();
}

void PageItem::keyReleaseEvent(QKeyEvent *event) {
    if (auto host = hostOf(m_client.get()))
        host->SendKeyEvent(Input::key(event, KEYEVENT_KEYUP));
    busy();
    m_keys.append(event->clone());
    m_keySent.append(nowNs());
    while (m_keys.size() > 32) {
        delete m_keys.takeFirst();
        m_keySent.removeFirst();
    }
    event->accept();
}

void PageItem::unhandledKey(int cefType, int nativeCode) {
    const QEvent::Type type = cefType == KEYEVENT_KEYUP ? QEvent::KeyRelease : QEvent::KeyPress;
    for (qsizetype i = 0; i < m_keys.size(); ++i) {
        QKeyEvent *key = m_keys.at(i);
        if (key->type() != type || int(key->nativeScanCode()) != nativeCode)
            continue;
        m_keys.removeAt(i);
        const qint64 sent = m_keySent.takeAt(i);
        // a printable key in a text field typed into it, though the page left it unhandled: it is not Opsis's
        // (Qt WebEngine counted it handled; so `/` types in a field instead of opening find)
        const bool typed = m_editable && !key->text().isEmpty() && key->text().at(0).isPrint()
            && !(key->modifiers() & (Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier));
        // Esc (Stop) handed back after a load began that started once it was pressed: it was for the page that load
        // replaces, and it stopped the new load (Esc, then an address: the address never loaded, 2026-10-15)
        const bool stale = key->key() == Qt::Key_Escape && m_loadStarted > sent;
        key->ignore();
        if (QQuickItem *parent = parentItem(); parent && !typed && !stale)
            QCoreApplication::sendEvent(parent, key);
        delete key;
        return;
    }
}

// ---- the clipboard, the desktop's through this window (kClipboardScript)

// a copy or a cut in the page: what it took onto the desktop's clipboard
void PageItem::copiedInPage(const QJsonObject &said) {
    auto *mime = new QMimeData;
    const QString text = said.value(QStringLiteral("text")).toString(), html = said.value(QStringLiteral("html")).toString();
    if (!text.isEmpty())
        mime->setText(text);
    if (!html.isEmpty())
        mime->setHtml(html);
    const QByteArray png = QByteArray::fromBase64(said.value(QStringLiteral("png")).toString().toLatin1());
    if (!png.isEmpty())
        mime->setData(QStringLiteral("image/png"), png);
    if (mime->formats().isEmpty()) {
        delete mime;
        return;
    }
    QGuiApplication::clipboard()->setMimeData(mime);
}

// the desktop's clipboard into the page: its text, and unless plain its HTML and a picture; false with no page yet
bool PageItem::pasteFromDesktop(bool plain) {
    if (!m_client || !m_client->browser())
        return false;
    const QMimeData *data = QGuiApplication::clipboard()->mimeData();
    QJsonObject held;
    if (data && data->hasText())
        held.insert(QStringLiteral("text"), data->text());
    if (data && !plain) {
        if (data->hasHtml())
            held.insert(QStringLiteral("html"), data->html());
        QByteArray png = data->data(QStringLiteral("image/png"));
        if (png.isEmpty() && data->hasImage()) {
            QBuffer buffer(&png);
            buffer.open(QIODevice::WriteOnly);
            qvariant_cast<QImage>(data->imageData()).save(&buffer, "PNG");
        }
        if (!png.isEmpty() && png.size() <= kMostPasted)
            held.insert(QStringLiteral("png"), QString::fromLatin1(png.toBase64()));
    }
    if (!held.isEmpty())
        m_client->paste(std::string(kPasteScript) + '(' + QJsonDocument(held).toJson(QJsonDocument::Compact).toStdString() + ')');
    busy();
    return true;
}

void PageItem::focusInEvent(QFocusEvent *event) {
    QQuickItem::focusInEvent(event);
    auto host = hostOf(m_client.get());
    if (traced)
        std::fprintf(stderr, "cef trace: page %p keys in (reason %d)%s\n", static_cast<void *>(this), event->reason(),
                     host ? "" : ", no page yet");
    if (host)
        host->SetFocus(true);
}

void PageItem::focusOutEvent(QFocusEvent *event) {
    QQuickItem::focusOutEvent(event);
    if (traced)
        std::fprintf(stderr, "cef trace: page %p keys out (reason %d)\n", static_cast<void *>(this), event->reason());
    if (auto host = hostOf(m_client.get()))
        host->SetFocus(false);
}

void PageItem::inputMethodEvent(QInputMethodEvent *event) {
    auto host = hostOf(m_client.get());
    if (!host)
        return;
    const CefRange none(UINT32_MAX, UINT32_MAX);
    if (!event->commitString().isEmpty())
        host->ImeCommitText(event->commitString().toStdString(), none, 0);
    if (!event->preeditString().isEmpty()) {
        int cursor = int(event->preeditString().size());
        for (const QInputMethodEvent::Attribute &a : event->attributes())
            if (a.type == QInputMethodEvent::Cursor)
                cursor = a.start;
        host->ImeSetComposition(event->preeditString().toStdString(), {}, none, CefRange(uint32_t(cursor), uint32_t(cursor)));
    } else if (event->commitString().isEmpty()) {
        host->ImeCancelComposition();
    }
    busy();
    event->accept();
}

// ---- drags

void PageItem::dragEnterEvent(QDragEnterEvent *event) {
    auto host = hostOf(m_client.get());
    if (!host)
        return event->ignore();
    m_dropOperation = -1;
    m_dragAsked = 1;
    host->DragTargetDragEnter(dragData(event->mimeData()), Input::mouse(event->position(), event->modifiers(), event->buttons()),
                              operations(event->possibleActions()));
    event->setDropAction(event->proposedAction());
    event->accept();
}

// the page says what it would do with the drag (UpdateDragCursor) a moment later; the last answer stands. Until it
// has said, the drag is taken as offered, as Qt WebEngine took it: refused, a quick drop would never reach the page
// (2026-10-08, the files checks' drops).
void PageItem::dragMoveEvent(QDragMoveEvent *event) {
    if (auto host = hostOf(m_client.get()); host && ++m_dragAsked)
        host->DragTargetDragOver(Input::mouse(event->position(), event->modifiers(), event->buttons()), operations(event->possibleActions()));
    if (m_dropOperation < 0) {
        event->setDropAction(event->proposedAction());
        event->accept();
        return;
    }
    const Qt::DropAction wanted = action(m_dropOperation);
    if (wanted == Qt::IgnoreAction) {
        event->ignore();
        return;
    }
    event->setDropAction(event->possibleActions() & wanted ? wanted : event->proposedAction());
    event->accept();
}

void PageItem::dragLeaveEvent(QDragLeaveEvent *) {
    if (auto host = hostOf(m_client.get()))
        host->DragTargetDragLeave();
}

void PageItem::dropAnswered(int operation) {
    m_dropOperation = operation;
    m_dragAsked = std::max(0, m_dragAsked - 1);
    if (m_dragAsked == 0)
        if (auto drop = std::exchange(m_heldDrop, nullptr))
            drop();
}

// A drop waits until the page has answered the drag's enter and every move (one answer each): CEF marks the drop with
// whether the document wanted the drag from the last answer, and before it the page neither gets the drop nor does
// Chromium open the file (2026-10-08, the files checks' quick drops were lost).
void PageItem::dropEvent(QDropEvent *event) {
    auto host = hostOf(m_client.get());
    if (!host)
        return event->ignore();
    const CefMouseEvent at = Input::mouse(event->position(), event->modifiers(), event->buttons());
    if (m_dragAsked > 0) {
        m_heldDrop = [host, at] { host->DragTargetDrop(at); };
        QTimer::singleShot(500, this, [this] {
            if (auto drop = std::exchange(m_heldDrop, nullptr))
                drop();
        });
        event->setDropAction(event->proposedAction());
        event->accept();
        return;
    }
    host->DragTargetDrop(at);
    const Qt::DropAction done = m_dropOperation < 0 ? Qt::IgnoreAction : action(m_dropOperation);
    event->setDropAction(event->possibleActions() & done ? done : event->proposedAction());
    event->accept();
}

void PageItem::startDrag(QMimeData *data, const QImage &image, QPoint hotspot, int allowed) {
    auto *drag = new QDrag(this);
    drag->setMimeData(data);
    if (!image.isNull()) {
        drag->setPixmap(QPixmap::fromImage(image));
        drag->setHotSpot(hotspot);
    }
    const Qt::DropAction done = drag->exec(actions(allowed) ? actions(allowed) : Qt::CopyAction);
    const QPointF at = mapFromGlobal(QCursor::pos());
    if (auto host = hostOf(m_client.get())) {
        host->DragSourceEndedAt(qRound(at.x()), qRound(at.y()), operations(done));
        host->DragSourceSystemDragEnded();
    }
}

QVariant PageItem::inputMethodQuery(Qt::InputMethodQuery query) const {
    switch (query) {
    case Qt::ImEnabled: return true;
    case Qt::ImCursorRectangle: return m_imeRect.isNull() ? QRectF(0, 0, 1, 20) : m_imeRect;
    case Qt::ImHints: return int(Qt::ImhNone);
    default: return QQuickItem::inputMethodQuery(query);
    }
}

// Security keys (book4-edge/cef-pgo/webauthn-patch.py): Opsis's CEF build says each step of a page's WebAuthn request
// to a listener on CEF's UI thread; it goes to the page by its browser's id, on Qt's thread, as webAuthnStep.
namespace {
QHash<int, QPointer<PageItem>> &webAuthnPages() {
    static QHash<int, QPointer<PageItem>> pages;
    return pages;
}
void webAuthnHeard(int browser, int request, const char *json) {
    const QByteArray data(json ? json : "{}");
    QMetaObject::invokeMethod(qApp, [browser, request, data] {
        if (PageItem *item = webAuthnPages().value(browser))
            emit item->webAuthnStep(request, QJsonDocument::fromJson(data).object().toVariantMap());
    }, Qt::QueuedConnection);
}
}

bool PageItem::webAuthnBridge() const {
    // the listener goes in once, before the first page's request can come
    static const bool can = [] {
        const auto listen = reinterpret_cast<void (*)(void (*)(int, int, const char *))>(dlsym(RTLD_DEFAULT, "cef_tacit_webauthn_listen"));
        if (listen)
            listen(&webAuthnHeard);
        return listen != nullptr;
    }();
    return can;
}

// DevTools open: the relay started, the front end loaded in `view` and pointed at it; closed: the relay goes, putting off
// what the front end left on
void PageItem::setDevToolsView(PageItem *view) {
    if (m_devToolsView == view)
        return;
    if (PageItem *was = m_devToolsView) {
        was->m_inspectedView = nullptr;
        emit was->inspectedViewChanged();
    }
    if (m_bridge) {
        delete std::exchange(m_bridge, nullptr);
        if (m_client)
            m_client->tapDevTools(false);
    }
    m_devToolsView = view;
    if (view) {
        const auto send = [this](const QByteArray &message) { if (m_client) m_client->sendDevTools(message); };
        // spare DevTools come loaded: their relay is given this page, what their front end said waiting goes to it
        const bool spare = view->m_spare;
        m_bridge = spare ? std::exchange(view->m_spare, nullptr) : new DevToolsBridge(send, this);
        m_bridge->setParent(this);
        connect(m_bridge, &DevToolsBridge::stateChanged, this, &PageItem::devToolsStateChanged);
        if (m_client)
            m_client->tapDevTools(true);
        if (spare)
            m_bridge->bind(send);
        view->m_inspectedView = this;
        emit view->inspectedViewChanged();
        if (!spare)
            view->setUrl(m_bridge->frontEndUrl());
    }
    emit devToolsViewChanged();
    emit devToolsStateChanged();
}

void PageItem::frameArrived() {
    ++m_arrived;
    if (m_holding && m_holdFrom >= 0 && m_arrived - m_holdFrom >= 2)
        endHold();
}

void PageItem::endHold() {
    if (!m_holding)
        return;
    m_holding = false;
    m_holdFrom = -1;
    m_holdLimit.stop();
    update();
}

// the last frame is the item's size (within the pixel PageNode::place allows): a resize has reached the screen
bool PageItem::frameFits() const {
    const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1;
    return !m_lastFrame.isEmpty() && qAbs(m_lastFrame.width() / dpr - width()) <= 1.5 && qAbs(m_lastFrame.height() / dpr - height()) <= 1.5;
}

void PageItem::prepareDevTools() {
    if (m_spare || m_inspectedView)
        return;
    m_spare = new DevToolsBridge({}, this);
    setUrl(m_spare->frontEndUrl());
}

QVariantMap PageItem::devToolsState() const {
    return m_bridge ? m_bridge->state() : QVariantMap();
}

void PageItem::fromDevTools(const QByteArray &message, qint64 id) {
    if (m_bridge)
        m_bridge->fromPage(message, id);
}

void PageItem::noteBrowser(int id) {
    // a page made anew (after a discard, a crash) under open DevTools: the relay listens to the new one
    if (m_bridge && m_client)
        m_client->tapDevTools(true);
    webAuthnBridge();
    webAuthnPages().insert(id, this);
}

void PageItem::webAuthnAnswer(int request, const QString &op, const QString &value) {
    static const auto answer = reinterpret_cast<void (*)(int, const char *, const char *)>(dlsym(RTLD_DEFAULT, "cef_tacit_webauthn_answer"));
    m_lastWebAuthnAnswer = QString::number(request) + u' ' + op;
    if (answer)
        answer(request, op.toUtf8().constData(), value.toUtf8().constData());
}

void PageItem::devtoolsCall(const QString &method, const QVariantMap &params) {
    if (m_client)
        m_client->devtoolsCall(method, QJsonObject::fromVariantMap(params));
}

// A page's history for another view (Windows::history): the engine's own entries with their page state, in Chrome's
// session format, from Opsis's CEF build (cef-tacit-history in book4-edge/cef-pgo/history-patch.py); "" from an engine
// without it, or when CEF's thread does not answer within a second (it may be waiting on this one).
QString PageItem::historyData() {
    static const auto save = reinterpret_cast<char *(*)(int)>(dlsym(RTLD_DEFAULT, "cef_tacit_history_save"));
    CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr;
    if (!save || !page)
        return {};
    struct Answer {
        QSemaphore done;
        QString data;
    };
    auto answer = std::make_shared<Answer>();
    CefPostTask(TID_UI, base::BindOnce([](int id, std::shared_ptr<Answer> a) {
        if (char *data = save(id)) {
            a->data = QString::fromLatin1(data);
            std::free(data);
        }
        a->done.release();
    }, page->GetIdentifier(), answer));
    return answer->done.tryAcquire(1, 1000) ? answer->data : QString();
}

void PageItem::setErrorPages(bool on) {
    m_errorPages = on;
    if (m_client)
        m_client->setErrorPages(on);
}

void PageItem::printToPdf(const QString &path, const QSizeF &paper, bool landscape, qreal margin, int from, int to,
                          bool backgrounds) {
    CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr;
    if (!page) {
        QMetaObject::invokeMethod(this, [this, path] { emit pdfPrintingFinished(path, false); }, Qt::QueuedConnection);
        return;
    }
    class Done : public CefPdfPrintCallback {
    public:
        explicit Done(PageItem *item) : m_item(item) {}
        void OnPdfPrintFinished(const CefString &path, bool ok) override {
            const QString file = QString::fromStdString(path.ToString());
            QMetaObject::invokeMethod(qApp, [item = m_item, file, ok] { if (item) emit item->pdfPrintingFinished(file, ok); },
                                      Qt::QueuedConnection);
        }
    private:
        QPointer<PageItem> m_item;
        IMPLEMENT_REFCOUNTING(Done);
    };
    CefPdfPrintSettings settings;
    settings.landscape = landscape;
    settings.print_background = backgrounds;
    settings.paper_width = paper.width();
    settings.paper_height = paper.height();
    settings.margin_type = PDF_PRINT_MARGIN_CUSTOM;
    settings.margin_top = settings.margin_right = settings.margin_bottom = settings.margin_left = margin;
    if (from > 0)
        CefString(&settings.page_ranges) = std::to_string(from) + "-" + std::to_string(std::max(from, to));
    page->GetHost()->PrintToPDF(path.toStdString(), settings, new Done(this));
}

// That history restored into this view, before it has loaded anything (Main's keepAt and reopened pages); false from an
// engine without Opsis's history patch, and the page then loads its address afresh
bool PageItem::restoreHistory(const QString &data) {
    static const bool can = dlsym(RTLD_DEFAULT, "cef_tacit_history_save") != nullptr;
    if (!can || data.isEmpty() || !m_url.isEmpty())
        return false;
    if (m_client)
        m_client->load(QUrl(QStringLiteral("opsis-restore:") + data));
    else
        m_restore = data;
    return true;
}

void PageItem::closeKept() {
    QHash<PageClient *, CefRefPtr<PageClient>> kept;
    {
        QMutexLocker lock(&PageClient::keptLock());
        kept = PageClient::keptPages();
    }
    for (const CefRefPtr<PageClient> &client : kept)
        client->closeKept();
}

void PageItem::registerQml(QQmlEngine *engine) {
    static const int registered = qmlRegisterType<PageItem>("Browser.Cef", 1, 0, "PageItem")
        + qmlRegisterType<ScriptCollection>("Browser.Cef", 1, 0, "ScriptCollection")
        + qmlRegisterSingletonInstance("Browser.Cef", 1, 0, "CefProfiles", CefProfiles::get());
    Q_UNUSED(registered)
    engine->addImportPath(QStringLiteral("qrc:/cefshim"));
}

void PageItem::setZoomFactor(qreal factor) {
    if (qFuzzyCompare(m_zoom, factor) || factor <= 0)
        return;
    m_zoom = factor;
    emit zoomFactorChanged();
    // Chromium's zoom level: each step is a factor of 1.2
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->GetHost()->SetZoomLevel(std::log(factor) / std::log(1.2));
}

void PageItem::goBack() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->GoBack();
}

void PageItem::goBackOrForward(int offset) {
    CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr;
    if (!page || offset == 0)
        return;
    if (tacitEngine)
        page->GetMainFrame()->LoadURL("opsis-history:" + std::to_string(offset));
    else if (offset == -1)
        page->GoBack();
    else if (offset == 1)
        page->GoForward();
}

void PageItem::goForward() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->GoForward();
}

void PageItem::loadHtml(const QString &html, const QUrl &baseUrl) {
    if (baseUrl.isEmpty()) {
        setUrl(QUrl(QStringLiteral("data:text/html;base64,") + QString::fromLatin1(html.toUtf8().toBase64())));
        return;
    }
    // the page may not be made yet (openNow hands it over then)
    m_givenUrl = baseUrl;
    m_givenHtml = html.toUtf8();
    if (m_client)
        m_client->giveHtml(std::exchange(m_givenUrl, QUrl()), std::exchange(m_givenHtml, QByteArray()));
    setUrl(baseUrl);
}

void PageItem::reload() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->Reload();
}

// Copy image (the page menu): the engine fetches the picture as the page has it (its cookies, its cache) and it goes on
// the desktop's clipboard as PNG; Chromium's own copy would put it on the clipboard this window cannot reach
class ImageCopy : public CefDownloadImageCallback {
public:
    void OnDownloadImageFinished(const CefString &, int, CefRefPtr<CefImage> image) override {
        int width = 0, height = 0;
        CefRefPtr<CefBinaryValue> png = image ? image->GetAsPNG(1.0f, true, width, height) : nullptr;
        if (!png || !png->GetSize())
            return;
        QByteArray bytes(qsizetype(png->GetSize()), Qt::Uninitialized);
        png->GetData(bytes.data(), png->GetSize(), 0);
        QMetaObject::invokeMethod(qApp, [bytes] {
            auto *mime = new QMimeData;
            mime->setData(QStringLiteral("image/png"), bytes);
            QGuiApplication::clipboard()->setMimeData(mime);
        });
    }
    IMPLEMENT_REFCOUNTING(ImageCopy);
};

void PageItem::triggerWebAction(int action) {
    CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr;
    if (!page)
        return;
    CefRefPtr<CefFrame> frame = page->GetFocusedFrame() ? page->GetFocusedFrame() : page->GetMainFrame();
    // WebEngineView.WebAction's numbers
    enum { Back, Forward, Stop, Reload, Cut, Copy, Paste, Undo, Redo, SelectAll, ReloadAndBypassCache, PasteAndMatchStyle,
           CopyImageToClipboard = 17, CopyImageUrlToClipboard = 18, DownloadImageToDisk = 19, InspectElement = 26, ExitFullScreen = 27, RequestClose = 28 };
    switch (action) {
    case Back: page->GoBack(); break;
    case Forward: page->GoForward(); break;
    case Stop: page->StopLoad(); break;
    case Reload: page->Reload(); break;
    case ReloadAndBypassCache: page->ReloadIgnoreCache(); break;
    case Cut: frame->Cut(); break;
    case Copy: frame->Copy(); break;
    case Paste: pasteFromDesktop(false); break;
    case PasteAndMatchStyle: pasteFromDesktop(true); break;
    case Undo: frame->Undo(); break;
    case Redo: frame->Redo(); break;
    case SelectAll: frame->SelectAll(); break;
    case CopyImageToClipboard: if (m_menuImage.isValid()) page->GetHost()->DownloadImage(m_menuImage.toString().toStdString(), false, 0, false, new ImageCopy); break;
    case CopyImageUrlToClipboard: if (m_menuImage.isValid()) QGuiApplication::clipboard()->setText(m_menuImage.toString()); break;
    case DownloadImageToDisk: if (m_menuImage.isValid()) page->GetHost()->StartDownload(m_menuImage.toString().toStdString()); break;
    // without this the close waited out BrowserView's 1 s limit (2026-10-07, the owner: closing a page lagged)
    case RequestClose: page->GetHost()->CloseBrowser(false); break;
    case ExitFullScreen: fullScreenCancelled(); break;
    // the element last right-clicked, in this page's DevTools (their view set first, as Qt's); the page's px are CSS px
    // times its zoom
    case InspectElement: if (m_bridge) m_bridge->inspectAt(m_menuPoint / m_zoom); break;
    default: break;
    }
}

void PageItem::fullScreenChanged(bool on, const QUrl &origin) {
    if (on == m_fullScreen)
        return;
    FullScreenRequest request;
    request.toggleOn = on;
    request.origin = origin;
    emit fullScreenRequested(&request);
    if (request.accepted || !on) {
        m_fullScreen = on;
        emit isFullScreenChanged();
    } else {
        fullScreenCancelled();
    }
}

void PageItem::findText(const QString &text, int flags, const QJSValue &callback) {
    CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr;
    if (!page)
        return;
    if (text.isEmpty()) {
        m_findText.clear();
        page->GetHost()->StopFinding(false);
        return;
    }
    m_findText = text;
    m_findCallback = callback;
    // CEF's last argument is Chromium's find_match: select a match. Off, a new search only highlights and the count
    // trails by one (2026-10-08). On, as Chrome's find bar has it: new text or case starts afresh at the first match,
    // the same again goes to the next.
    page->GetHost()->Find(text.toStdString(), !(flags & 1), flags & 2, true);
}

void PageItem::found(int matches, int active) {
    if (m_findText.isEmpty())
        return;     // stopped since
    emit findTextFinished({{QStringLiteral("numberOfMatches"), matches}, {QStringLiteral("activeMatch"), matches ? active : 0}});
    if (QJSValue callback = std::exchange(m_findCallback, QJSValue()); callback.isCallable())
        callback.call({matches > 0});
}

void PageItem::fullScreenCancelled() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->GetHost()->ExitFullscreen(true);
}

void PageItem::replaceMisspelledWord(const QString &replacement) {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->GetHost()->ReplaceMisspelling(replacement.toStdString());
}

void PageItem::reloadAndBypassCache() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->ReloadIgnoreCache();
}

void PageItem::setUnresponsive(bool on) {
    if (std::exchange(m_unresponsive, on) != on)
        emit unresponsiveChanged();
}

void PageItem::waitForPage() {
    if (m_client)
        m_client->waitForPage();
}

void PageItem::endAndReload() {
    if (!m_client)
        return;
    m_client->endAndReload();
    // The engine asks the page's process to exit; one whose thread is stuck in a send to the browser never finishes
    // exiting, and the page stayed "not answering" for minutes (VM test 2026-10-24: every thread in do_exit but one).
    // Still there 2 s on, the process is killed, as Chrome's task manager ends one: its end reloads the page.
    const qint64 pid = m_renderPid;
    if (pid <= 1)
        return;
    QTimer::singleShot(2000, this, [this, pid] {
        if (m_renderPid != pid)
            return;
        // only this page's process, which runs the engine's helper beside this program
        const QString exe = QFile::symLinkTarget(QStringLiteral("/proc/%1/exe").arg(pid));
        if (!exe.isEmpty() && QFileInfo(exe).fileName().startsWith(u"browser-page"))
            ::kill(pid_t(pid), SIGKILL);
    });
}

void PageItem::stop() {
    if (CefRefPtr<CefBrowser> page = m_client ? m_client->browser() : nullptr)
        page->StopLoad();
}

void PageItem::runJavaScript(const QString &script, const QJSValue &worldOrCallback, const QJSValue &callback) {
    const QJSValue &answer = worldOrCallback.isCallable() ? worldOrCallback : callback;
    const int world = worldOrCallback.isNumber() ? worldOrCallback.toInt() : 0;
    if (!m_client) {
        if (answer.isCallable())
            QMetaObject::invokeMethod(this, [answer] { QJSValue(answer).call({QJSValue()}); }, Qt::QueuedConnection);
        return;
    }
    const int call = ++m_lastCall;
    if (answer.isCallable())
        m_calls.insert(call, answer);
    m_client->evaluate(call, script, world);
}

// Runtime.evaluate's answer: { result: { type, value } }, or with exceptionDetails when the script threw
void PageItem::answered(int call, bool done, const QByteArray &json) {
    QJSValue answer = m_calls.take(call);
    if (!answer.isCallable())
        return;
    const QJsonObject reply = QJsonDocument::fromJson(json).object();
    const QJsonObject result = reply.value(QStringLiteral("result")).toObject();
    QJSEngine *engine = qjsEngine(this);
    if (!done || !engine || reply.contains(QStringLiteral("exceptionDetails")) || !result.contains(QStringLiteral("value")))
        answer.call({QJSValue()});
    else
        answer.call({engine->toScriptValue(result.value(QStringLiteral("value")).toVariant())});
}

// As Qt WebEngine's view, an address set is loaded even when it is the one shown (Continue on a certificate's page
// over the page it questioned loads that page again)
void PageItem::setUrl(const QUrl &url) {
    if (m_url != url) {
        m_url = url;
        emit urlChanged();
    }
    if (m_client)
        m_client->load(url);
    else
        open();
}

void PageItem::componentComplete() {
    QQuickItem::componentComplete();
    open();
}

void PageItem::itemChange(ItemChange change, const ItemChangeData &data) {
    QQuickItem::itemChange(change, data);
    if (change == ItemSceneChange && data.window) {
        if (traced)
            connect(data.window, &QQuickWindow::frameSwapped, this, &PageItem::traceSwapped, Qt::UniqueConnection);
        if (!ownBeat)
            connect(data.window, &QQuickWindow::frameSwapped, this, &PageItem::windowBeat, Qt::UniqueConnection);
        open();
    } else if (change == ItemDevicePixelRatioHasChanged && m_client) {
        if (traced)
            std::fprintf(stderr, "cef trace: pixel ratio changed to %.2f (window %.2f)\n", data.realValue,
                         window() ? window()->effectiveDevicePixelRatio() : 0.0);
        // A screen's scale changed in Settings: Hyprland resizes the window first and the new ratio comes after, so the
        // size alone left the page drawn at the old scale, in the top left 1/scale of its window (Discord 2026-10-24,
        // Tamrawii, 100 % to 125 %)
        m_client->resize(size().toSize(), window() ? window()->effectiveDevicePixelRatio() : data.realValue,
                         mapToGlobal(QPointF()).toPoint());
        busy();
        beginFrame();
        m_refreshes = 2;
        m_refresh.start(60);
    } else if (change == ItemVisibleHasChanged && m_client) {
        if (traced && data.boolValue) {
            m_traceShow = nowNs();
            m_traceShowFrame = -1;
            m_traceShowDrawn = false;
        }
        m_client->hide(!data.boolValue);
        if (data.boolValue)
            busy();
        else
            m_beat.stop();
    }
}

void PageItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() == oldGeometry.size())
        return;
    if (m_client) {
        const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1;
        if (!m_lastFrame.isEmpty()) {
            m_holding = true;
            m_holdFrom = -1;
            m_holdLimit.start();
        }
        m_client->resize(newGeometry.size().toSize(), dpr, mapToGlobal(QPointF()).toPoint());
        if (traced) {
            m_resizedAt = nowNs();
            m_resizeTarget = (QSizeF(newGeometry.size().toSize()) * dpr).toSize();
        }
        // With Opsis's own beat (OPSIS_CEF_BEAT) a new size is activity: the quick beat and a begin frame now
        busy();
        beginFrame();
        // CEF sends a frame only when the page changes: during a burst of resizes (a window re-tiled while another program
        // opens) the frame for the last size could be missed, and a still page then stayed at an old size, cropped, until
        // something on it moved (2026-10-08). Once the size settles, a fresh frame is asked for, and once more after.
        m_refreshes = 2;
        m_refresh.start(60);
    } else {
        open();
    }
}

void PageItem::setLifecycleState(int state) {
    if (state == m_lifecycle)
        return;
    const int was = std::exchange(m_lifecycle, state);
    if (state == 2 && m_client) {
        // its back/forward list first (an engine without the history patch gives none: it loads its address again)
        m_restore = historyData();
        m_client->close();
        m_client = nullptr;
        m_frames.reset();
        m_popupFrames.reset();
        if (m_renderPid) {
            m_renderPid = 0;
            emit renderProcessPidChanged();
        }
        setUnresponsive(false);
        if (std::exchange(m_loading, false))
            emit loadingChanged({{QStringLiteral("status"), 1}, {QStringLiteral("url"), m_url}});
        update();
    }
    emit lifecycleStateChanged();
    if (was == 2 && state != 2)
        open();
}

void PageItem::open() {
    if (m_client || m_opening || !isComponentComplete() || !window() || width() < 1 || height() < 1)
        return;
    m_opening = true;
    QMetaObject::invokeMethod(this, &PageItem::openNow, Qt::QueuedConnection);
}

CefRefPtr<PageClient> PageItem::adopt() {
    if (m_client)
        return nullptr;     // already has a page of its own
    m_shared = window() && sharedFrames(window());
    if (m_shared)
        Copier::get().prepare();
    m_frames = std::make_shared<PageFrames>();
    m_popupFrames = std::make_shared<PageFrames>();
    m_client = new PageClient(this, m_frames, m_popupFrames);
    m_client->setFilter(filterOf(m_profile));
    if (!m_errorPages)
        m_client->setErrorPages(false);
    m_client->attach(this, size().toSize(), window() ? window()->effectiveDevicePixelRatio() : 1, mapToGlobal(QPointF()).toPoint());
    CefRuntime::pageOpening();
    return m_client;
}

void PageItem::openNow() {
    m_opening = false;
    if (m_client || !window() || width() < 1 || height() < 1)
        return;
    const bool shared = sharedFrames(window());
    if (shared)
        Copier::get().prepare();
    if (m_shared != shared) {
        m_shared = shared;
        emit sharedChanged();
    }
    m_frames = std::make_shared<PageFrames>();
    m_popupFrames = std::make_shared<PageFrames>();
    m_client = new PageClient(this, m_frames, m_popupFrames);
    m_client->setFilter(filterOf(m_profile));
    if (!m_errorPages)
        m_client->setErrorPages(false);
    if (!m_givenUrl.isEmpty())
        m_client->giveHtml(std::exchange(m_givenUrl, QUrl()), std::exchange(m_givenHtml, QByteArray()));
    m_client->resize(size().toSize(), window()->effectiveDevicePixelRatio(), mapToGlobal(QPointF()).toPoint());
    if (!isVisible())
        m_client->hide(true);

    CefWindowInfo info;
    info.SetAsWindowless(0);
    info.shared_texture_enabled = shared;
    info.external_begin_frame_enabled = !ownBeat;
    CefBrowserSettings settings;
    const int rate = window()->screen() ? qRound(window()->screen()->refreshRate()) : 60;
    // twice the screen's: at the screen's own rate a page frame a little late waited a whole frame more, and anything
    // moving ran at half rate (2026-10-11, a chat list scrolled on a 60 Hz screen: 46 page frames a second, 33 ms apart
    // at worst; at 120: 89, 17 ms; the owner: WhatsApp and Gmail lagging behind the hand). Twice the drawing while
    // something moves, none more at rest. With the beat it is only the capture's rate, so it never drops an early frame.
    settings.windowless_frame_rate = 2 * rate;
    // OPSIS_CEF_FPS: another rate, to try
    if (const int fps = qEnvironmentVariableIntValue("OPSIS_CEF_FPS"))
        settings.windowless_frame_rate = fps;
    // white where a page sets no ground (backgroundColor), as Qt WebEngine and every browser draw it; an off-screen page's
    // default is see-through, and the window's frost showed behind such pages (2026-10-07, browserbench.org)
    settings.background_color = CefColorSetARGB(255, m_background.red(), m_background.green(), m_background.blue());
    CefRuntime::pageOpening();
    // blank until its scripts are in (PageClient::loadPending), then the address
    m_restorePending = !m_restore.isEmpty();
    if (m_restorePending)
        m_client->load(QUrl(QStringLiteral("opsis-restore:") + std::exchange(m_restore, QString())));
    else if (!m_url.isEmpty())
        m_client->load(m_url);
    CefRefPtr<CefDictionaryValue> scripts = nativeRoute ? m_client->startScripts(specsOf(m_profile, m_userScripts)) : nullptr;
    // a page made to take a history (restoreHistory) starts on no address: a pending about:blank load would outlast the
    // restore, and Chromium's Restore wants a page that has loaded nothing
    const std::string first = m_restorePending ? std::string() : std::string("about:blank");
    if (!CefBrowserHost::CreateBrowser(info, m_client, first, settings, scripts, contextOf(m_profile))) {
        CefRuntime::pageClosed();
        qWarning("PageItem: CEF made no page for %s", qPrintable(m_url.toString()));
    }
    busy();
}

// ---- profiles

// The page's profile as CEF's request context. The main profile is the global one (its data under the root cache path);
// a private window's (off the record: no storage name) gets its own in memory, so private windows share no cookies,
// storage or cache with the main profile or each other. Made once per profile object, on Qt's thread; it goes with it.
namespace {
class PrivateContext : public CefRequestContextHandler {
public:
    // as the global context (runtime.cpp, OnContextInitialized): a page's downloads all go ahead, and every pop-up
    // comes to Opsis to refuse or open
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
        context->SetContentSetting(CefString(), CefString(), CEF_CONTENT_SETTING_TYPE_AUTOMATIC_DOWNLOADS,
                                   CEF_CONTENT_SETTING_VALUE_ALLOW);
        context->SetContentSetting(CefString(), CefString(), CEF_CONTENT_SETTING_TYPE_POPUPS, CEF_CONTENT_SETTING_VALUE_ALLOW);
        // no dictionary fetched from Google (runtime.cpp, noDictionaryFetch)
        CefRefPtr<CefValue> off = CefValue::Create();
        off->SetBool(false);
        CefString error;
        context->SetPreference("browser.enable_spellchecking", off, error);
    }
    IMPLEMENT_REFCOUNTING(PrivateContext);
};
QHash<QObject *, CefRefPtr<CefRequestContext>> &privateContexts() {
    static QHash<QObject *, CefRefPtr<CefRequestContext>> contexts;
    return contexts;
}
// Pages take the desktop's light or dark (prefers-color-scheme, form controls, scroll bars) as Qt WebEngine's did through
// Qt: Chromium in CEF reads no desktop setting of its own here, and pages were light on Tacit's dark (2026-10-11). Set on
// a context when it is first used, and on all of them again when the desktop changes.
void followDesktop(CefRefPtr<CefRequestContext> context) {
    const Qt::ColorScheme scheme = QGuiApplication::styleHints()->colorScheme();
    context->SetChromeColorScheme(scheme == Qt::ColorScheme::Dark ? CEF_COLOR_VARIANT_DARK
                                  : scheme == Qt::ColorScheme::Light ? CEF_COLOR_VARIANT_LIGHT : CEF_COLOR_VARIANT_SYSTEM, 0);
}
// No form memory of Chromium's: it kept what was typed into a page's fields (user names among them) in the profile's
// Web Data, under the passwords group's check that no profile file holds one (2026-10-14), and Opsis offers its own
// logins and fills no addresses or cards (Settings says so). autofill.profile_enabled is also what turns autocomplete on.
void noFormMemory(CefRefPtr<CefRequestContext> context) {
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefRequestContext> c) {
        for (const char *name : {"autofill.profile_enabled", "autofill.credit_card_enabled"}) {
            CefRefPtr<CefValue> off = CefValue::Create();
            off->SetBool(false);
            CefString error;
            if (!c->SetPreference(name, off, error))
                std::fprintf(stderr, "browser: %s not turned off: %s\n", name, error.ToString().c_str());
        }
    }, context));
}
CefRefPtr<CefRequestContext> contextOf(QObject *profile) {
    static const bool following = [] {
        followDesktop(CefRequestContext::GetGlobalContext());
        noFormMemory(CefRequestContext::GetGlobalContext());
        QObject::connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, qApp, [] {
            followDesktop(CefRequestContext::GetGlobalContext());
            for (const CefRefPtr<CefRequestContext> &context : std::as_const(privateContexts()))
                followDesktop(context);
        });
        return true;
    }();
    Q_UNUSED(following)
    if (!profile || !profile->property("offTheRecord").toBool())
        return nullptr;
    if (CefRefPtr<CefRequestContext> known = privateContexts().value(profile))
        return known;
    CefRequestContextSettings settings;     // no cache path: everything in memory
    CefRefPtr<CefRequestContext> made = CefRequestContext::CreateContext(settings, new PrivateContext());
    followDesktop(made);
    noFormMemory(made);
    privateContexts().insert(profile, made);
    QObject::connect(profile, &QObject::destroyed, [profile] { privateContexts().remove(profile); });
    return made;
}
CefRefPtr<CefCookieManager> cookiesOf(QObject *profile) {
    CefRefPtr<CefRequestContext> context = contextOf(profile);
    return (context ? context : CefRequestContext::GetGlobalContext())->GetCookieManager(nullptr);
}
// collects the store's cookies; when CEF lets the visitor go (after the last one, or at once with none), hands them over
class CookieList : public CefCookieVisitor {
public:
    CookieList(QObject *receiver, std::function<void(const QList<CefCookies::Cookie> &)> done)
        : m_receiver(receiver), m_done(std::move(done)) {}
    ~CookieList() override {
        QMetaObject::invokeMethod(qApp, [receiver = m_receiver, done = std::move(m_done), cookies = std::move(m_cookies)] {
            if (receiver)
                done(cookies);
        }, Qt::QueuedConnection);
    }
    bool Visit(const CefCookie &c, int, int, bool &) override {
        CefCookies::Cookie k;
        k.name = QString::fromStdString(CefString(&c.name).ToString());
        k.domain = QString::fromStdString(CefString(&c.domain).ToString());
        k.path = QString::fromStdString(CefString(&c.path).ToString());
        k.secure = c.secure;
        k.httpOnly = c.httponly;
        k.sameSite = int(c.same_site);
        k.expires = c.has_expires ? qint64(CefBaseTime(c.expires).val / 1000 - 11644473600000LL) : 0;   // from 1601, in us
        m_cookies.append(k);
        return true;
    }
private:
    QPointer<QObject> m_receiver;
    std::function<void(const QList<CefCookies::Cookie> &)> m_done;
    QList<CefCookies::Cookie> m_cookies;
    IMPLEMENT_REFCOUNTING(CookieList);
};
}

void CefCookies::list(QObject *profile, QObject *receiver, std::function<void(const QList<Cookie> &)> done) {
    // on CEF's UI thread, after any delete or set asked for before it (they go there too)
    CefRefPtr<CefCookieManager> manager = cookiesOf(profile);
    if (!manager)
        return;
    CefRefPtr<CookieList> visitor = new CookieList(receiver, std::move(done));
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefCookieManager> m, CefRefPtr<CookieList> v) {
        m->VisitAllCookies(v);
    }, manager, visitor));
}
namespace {
void cookiesTouched();
// counts the answers to a batch of SetCookie, then tells Qt's thread (and SiteData, which lists the store again)
class CookieSetting : public CefSetCookieCallback {
public:
    CookieSetting(int total, QObject *receiver, std::function<void(int, int)> done) : m_total(total), m_receiver(receiver), m_done(std::move(done)) {}
    void OnComplete(bool success) override {
        const int set = success ? ++m_set : m_set.load(), refused = success ? m_refused.load() : ++m_refused;
        if (set + refused != m_total)
            return;
        QMetaObject::invokeMethod(qApp, [receiver = m_receiver, done = m_done, set, refused] {
            if (receiver)
                done(set, refused);
        }, Qt::QueuedConnection);
        cookiesTouched();
    }
private:
    const int m_total;
    std::atomic<int> m_set{0}, m_refused{0};
    QPointer<QObject> m_receiver;
    std::function<void(int, int)> m_done;
    IMPLEMENT_REFCOUNTING(CookieSetting);
};
}
void CefCookies::set(QObject *profile, const QList<Set> &cookies, QObject *receiver, std::function<void(int, int)> done) {
    CefRefPtr<CefCookieManager> manager = cookiesOf(profile);
    if (!manager)
        manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager || cookies.isEmpty()) {
        const int n = int(cookies.size());
        QMetaObject::invokeMethod(qApp, [receiver = QPointer<QObject>(receiver), done, n] { if (receiver) done(0, n); }, Qt::QueuedConnection);
        return;
    }
    CefRefPtr<CookieSetting> counter = new CookieSetting(int(cookies.size()), receiver, std::move(done));
    // SetCookie on CEF's UI thread, as the preferences are set
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefCookieManager> m, QList<CefCookies::Set> list, CefRefPtr<CookieSetting> c) {
        for (const CefCookies::Set &s : list) {
            CefCookie k;
            CefString(&k.name) = s.name.toStdString();
            CefString(&k.value) = s.value.toStdString();
            // a host-only cookie (its host without a leading dot, as Chromium and Firefox file them) has no domain in
            // CEF; given its host as a domain it became a domain cookie, which an address like 127.0.0.1 never gets
            if (s.domain.startsWith(u'.'))
                CefString(&k.domain) = s.domain.toStdString();
            CefString(&k.path) = (s.path.isEmpty() ? QStringLiteral("/") : s.path).toStdString();
            k.secure = s.secure;
            k.httponly = s.httpOnly;
            k.same_site = cef_cookie_same_site_t(s.sameSite);
            k.priority = CEF_COOKIE_PRIORITY_MEDIUM;
            k.has_expires = s.expires > 0;
            if (k.has_expires)
                k.expires.val = (s.expires + 11644473600000LL) * 1000;     // to 1601, in us
            const QString host = s.domain.startsWith(u'.') ? s.domain.mid(1) : s.domain;
            const std::string url = (s.secure ? "https://" : "http://") + host.toStdString() + (s.path.isEmpty() ? std::string("/") : s.path.toStdString());
            if (!m->SetCookie(url, k, c))
                c->OnComplete(false);
        }
        m->FlushStore(nullptr);
    }, manager, cookies, counter));
}
void CefCookies::remove(QObject *profile, const QString &url, const QString &name) {
    // on CEF's UI thread, as SetCookie (called from Qt's, Clear browsing data left every cookie, 2026-10-15)
    if (CefRefPtr<CefCookieManager> manager = cookiesOf(profile))
        CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefCookieManager> m, std::string u, std::string n) {
            m->DeleteCookies(u, n, nullptr);
            m->FlushStore(nullptr);
        }, manager, url.toStdString(), name.toStdString()));
}

// ---- CefProfiles
namespace {
CefRefPtr<CefValue> toCef(const QVariant &v) {
    if (!v.isValid() || v.isNull())
        return nullptr;
    CefRefPtr<CefValue> out = CefValue::Create();
    switch (v.typeId()) {
    case QMetaType::Bool: out->SetBool(v.toBool()); break;
    case QMetaType::Int: case QMetaType::LongLong: out->SetInt(v.toInt()); break;
    case QMetaType::Double: {
        const double d = v.toDouble();     // QML's numbers are doubles: whole ones go as Chromium's ints
        if (d == std::floor(d))
            out->SetInt(int(d));
        else
            out->SetDouble(d);
        break;
    }
    case QMetaType::QStringList: case QMetaType::QVariantList: {
        CefRefPtr<CefListValue> list = CefListValue::Create();
        const QVariantList items = v.toList();
        for (int i = 0; i < items.size(); ++i)
            list->SetString(i, items[i].toString().toStdString());
        out->SetList(list);
        break;
    }
    default: out->SetString(v.toString().toStdString());
    }
    return out;
}
QVariant fromCef(CefRefPtr<CefValue> v) {
    if (!v)
        return {};
    switch (v->GetType()) {
    case VTYPE_BOOL: return v->GetBool();
    case VTYPE_INT: return v->GetInt();
    case VTYPE_DOUBLE: return v->GetDouble();
    case VTYPE_STRING: return QString::fromStdString(v->GetString().ToString());
    case VTYPE_LIST: {
        QStringList out;
        CefRefPtr<CefListValue> list = v->GetList();
        for (size_t i = 0; i < list->GetSize(); ++i)
            out.append(QString::fromStdString(list->GetString(i).ToString()));
        return out;
    }
    default: return {};
    }
}
CefRefPtr<CefRequestContext> requestContextOf(QObject *profile) {
    CefRefPtr<CefRequestContext> context = contextOf(profile);
    return context ? context : CefRequestContext::GetGlobalContext();
}
}

CefProfiles *CefProfiles::get() {
    static CefProfiles *one = new CefProfiles(qApp);
    return one;
}

QVariantMap CefProfiles::preferences(QObject *profile, const QStringList &names) const {
    struct Answer {
        QSemaphore done;
        QVariantMap values;
    };
    auto answer = std::make_shared<Answer>();
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefRequestContext> c, QStringList list, std::shared_ptr<Answer> a) {
        for (const QString &n : list)
            a->values.insert(n, fromCef(c->GetPreference(n.toStdString())));
        a->done.release();
    }, requestContextOf(profile), names, answer));
    return answer->done.tryAcquire(1, 1000) ? answer->values : QVariantMap();
}

QVariant CefProfiles::preference(QObject *profile, const QString &name) const {
    return preferences(profile, {name}).value(name);
}

void CefProfiles::setPreference(QObject *profile, const QString &name, const QVariant &value) {
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefRequestContext> c, std::string n, CefRefPtr<CefValue> v) {
        CefString error;
        if (!c->SetPreference(n, v, error))
            std::fprintf(stderr, "browser: preference %s not set: %s\n", n.c_str(), error.ToString().c_str());
    }, requestContextOf(profile), name.toStdString(), toCef(value)));
}

void CefProfiles::clearHttpCache(QObject *profile) {
    class Done : public CefCompletionCallback {
    public:
        explicit Done(QObject *profile) : m_profile(profile) {}
        void OnComplete() override {
            QMetaObject::invokeMethod(qApp, [p = m_profile] { if (p) emit CefProfiles::get()->httpCacheCleared(p); },
                                      Qt::QueuedConnection);
        }
    private:
        QPointer<QObject> m_profile;
        IMPLEMENT_REFCOUNTING(Done);
    };
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefRequestContext> c, CefRefPtr<CefCompletionCallback> done) {
        c->ClearHttpCache(done);
    }, requestContextOf(profile), CefRefPtr<CefCompletionCallback>(new Done(profile))));
}

QString CefProfiles::dataPath() const {
    return CefRuntime::dataPath();
}
namespace {
QList<std::pair<QPointer<QObject>, std::function<void()>>> &touchedCalls() {     // Qt's thread
    static QList<std::pair<QPointer<QObject>, std::function<void()>>> calls;
    return calls;
}
void cookiesTouched() {
    QMetaObject::invokeMethod(qApp, [] {
        auto &calls = touchedCalls();
        calls.removeIf([](const auto &c) { return !c.first; });
        for (const auto &c : std::as_const(calls))
            c.second();
    }, Qt::QueuedConnection);
}
}
void CefCookies::onTouched(QObject *owner, std::function<void()> call) {
    touchedCalls().append({owner, std::move(call)});
}
void CefCookies::refuseThirdParty(QObject *profile, bool refuse) {
    CefRefPtr<CefRequestContext> context = contextOf(profile);
    if (!context)
        context = CefRequestContext::GetGlobalContext();
    // Chromium's cookie controls: 1 blocks third-party cookies, 0 allows them (preferences are set on CEF's UI thread)
    CefPostTask(TID_UI, base::BindOnce([](CefRefPtr<CefRequestContext> c, bool r) {
        CefRefPtr<CefValue> v = CefValue::Create();
        v->SetInt(r ? 1 : 0);
        CefString error;
        c->SetPreference("profile.cookie_controls_mode", v, error);
    }, context, refuse));
}

// ---- the beat

void PageItem::beginFrame() {
    if (ownBeat || !isVisible())
        return;
    if (auto host = m_client && m_client->browser() ? m_client->browser()->GetHost() : nullptr) {
        host->SendExternalBeginFrame();     // CEF skips it while the last one is still being drawn
        m_lastBegin = nowNs();
    }
}

void PageItem::windowBeat() {
    beginFrame();
    // while the page moves, the window keeps drawing, so the next begin frame comes on the screen's beat too
    if (m_client && isVisible() && nowNs() - m_lastBusy < 250'000'000)
        update();
}

void PageItem::refreshFrame() {
    if (auto host = m_client && m_client->browser() ? m_client->browser()->GetHost() : nullptr)
        host->Invalidate(PET_VIEW);
    if (--m_refreshes > 0)
        m_refresh.start(250);
}

void PageItem::traceResized(QSize got) {
    if (!m_resizedAt || got.isEmpty() || qAbs(got.width() - m_resizeTarget.width()) > 2 || qAbs(got.height() - m_resizeTarget.height()) > 2)
        return;
    std::fprintf(stderr, "cef trace: page %dx%d on screen %.1f ms after its resize\n", got.width(), got.height(), (nowNs() - m_resizedAt) / 1e6);
    m_resizedAt = 0;
}

void PageItem::beatTick() {
    const qint64 now = nowNs();
    // only when the window has not given one for more than a frame: it rests, or missed the screen
    if (now - m_lastBegin > 24'000'000)
        beginFrame();
    // quick (the screen's rate) for 2 s after the page drew or was touched and while it loads, then 10 a second
    const int interval = m_loading || now - m_lastBusy < 2'000'000'000 ? 16 : 100;
    if (m_beat.interval() != interval)
        m_beat.setInterval(interval);
}

void PageItem::busy() {
    if (ownBeat)
        return;
    const qint64 now = nowNs();
    const bool resting = now - m_lastBegin > 20'000'000;
    m_lastBusy = now;
    if (!m_client || !isVisible())
        return;
    if (!m_beat.isActive() || m_beat.interval() != 16)
        m_beat.start(16);
    // touched while the window rests: a begin frame now, not at the next tick
    if (resting)
        beginFrame();
}

QSGNode *PageItem::updatePaintNode(QSGNode *old, UpdatePaintNodeData *) {
    auto *node = static_cast<PageNode *>(old);
    if (!m_frames) {
        if (m_lifecycle == 2) {     // discarded: its frames (and the textures the node wraps) are gone
            delete node;
            return nullptr;
        }
        return node;
    }
    // a resize's hold: the frame on screen stays, placed in the new box (1:1, cropped where the box is smaller)
    if (m_holding && node) {
        node->place(boundingRect(), window()->effectiveDevicePixelRatio());
        return node;
    }
    const PageFrames::Shown shown = m_frames->take();
    if (!shown.texture && shown.image.isNull() && !(node && node->uploaded))
        return node;        // no frame yet
    if (!node) {
        node = new PageNode;
        node->frames = m_frames;
        node->setFiltering(QSGTexture::Linear);
    }
    node->show(window(), shown);
    node->place(boundingRect(), window()->effectiveDevicePixelRatio());
    // the page's own pop-up (a select's list), where the page puts it
    if (m_popupShown && m_popupFrames) {
        // the node waits for the pop-up's first frame: a texture node with no texture would crash the renderer
        const PageFrames::Shown popup = m_popupFrames->take();
        if (!node->popup) {
            auto *made = new PageNode;
            made->frames = m_popupFrames;
            made->setFiltering(QSGTexture::Linear);
            if (made->show(window(), popup)) {
                node->popup = made;
                node->appendChildNode(made);
            } else {
                delete made;
            }
        } else {
            node->popup->show(window(), popup);
        }
        if (node->popup)
            node->popup->setRect(m_popupRect);
    } else if (node->popup) {
        node->removeChildNode(node->popup);
        delete node->popup;
        node->popup = nullptr;
    }
    return node;
}
