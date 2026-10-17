#include <dlfcn.h>
#include <cmath>
#include <cstdlib>
#include <map>
#include <set>
#include <string>
#include <vector>
// A page process (renderer, GPU, network, ...): CEF starts this executable for each of them
// (CefSettings.browser_subprocess_path, src/cef/runtime.cpp), so none of them loads Qt.
#include "include/base/cef_compiler_specific.h"
#include "include/cef_app.h"
#include "include/cef_command_line.h"
#include "include/cef_parser.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"

namespace {

// Opsis's own script world in the engine (~/dev/tacit-web/cef-tacit-opsis-world.patch): its id, 0 on an engine without
// it. Opsis's side (src/cef/pageitem.cpp) takes the DevTools route then, and none of this is asked.
int opsisWorld() {
    static const int id = [] {
        const auto probe = reinterpret_cast<int (*)()>(dlsym(RTLD_DEFAULT, "cef_tacit_opsis_world"));
        return probe ? probe() : 0;
    }();
    return id;
}

struct Script {
    std::string key, source;
    bool opsis = false;     // Opsis's world, else the page's own
};

// `__opsis(text)` in Opsis's world: the text to the page's item (PageClient::OnProcessMessageReceived)
class Bridge : public CefV8Handler {
public:
    bool Execute(const CefString &, CefRefPtr<CefV8Value>, const CefV8ValueList &arguments, CefRefPtr<CefV8Value> &,
                 CefString &) override {
        CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
        CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
        if (frame && arguments.size() == 1 && arguments[0]->IsString()) {
            CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("opsis.bridge");
            message->GetArgumentList()->SetString(0, arguments[0]->GetStringValue());
            frame->SendProcessMessage(PID_BROWSER, message);
        }
        return true;
    }
    IMPLEMENT_REFCOUNTING(Bridge);
};

// `print()` in a document's main world, every frame's (window.print): Chromium's own print preview cannot open
// off-screen ("Something went wrong when trying to print"), so the call goes to the page's item, which asks as Qt
// WebEngine's printRequested does (Opsis's print card). It returns at once; the page does not wait for the print.
class Print : public CefV8Handler {
public:
    bool Execute(const CefString &, CefRefPtr<CefV8Value>, const CefV8ValueList &, CefRefPtr<CefV8Value> &, CefString &) override {
        CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
        CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
        if (frame)
            frame->SendProcessMessage(PID_BROWSER, CefProcessMessage::Create("opsis.print"));
        return true;
    }
    IMPLEMENT_REFCOUNTING(Print);
};

// A script's answer as plain values, as DevTools' returnByValue gave it: functions and numbers JSON cannot hold become
// null; a value that holds itself, or one too big, fails. In an entered context.
bool plain(CefRefPtr<CefV8Value> v, std::vector<CefRefPtr<CefV8Value>> &path, int &budget, CefRefPtr<CefValue> out) {
    if (--budget < 0)
        return false;
    if (!v || v->IsNull() || v->IsUndefined() || v->IsFunction())
        out->SetNull();
    else if (v->IsBool())
        out->SetBool(v->GetBoolValue());
    else if (v->IsInt())
        out->SetInt(v->GetIntValue());
    else if (v->IsDouble()) {
        const double d = v->GetDoubleValue();
        if (std::isfinite(d))
            out->SetDouble(d);
        else
            out->SetNull();
    }
    else if (v->IsString())
        out->SetString(v->GetStringValue());
    else if (v->IsArray() || v->IsObject()) {
        for (const CefRefPtr<CefV8Value> &held : path)
            if (held->IsSame(v))
                return false;
        path.push_back(v);
        bool done = true;
        if (v->IsArray()) {
            CefRefPtr<CefListValue> list = CefListValue::Create();
            for (int i = 0, n = v->GetArrayLength(); done && i < n; ++i) {
                CefRefPtr<CefValue> item = CefValue::Create();
                done = plain(v->GetValue(i), path, budget, item);
                list->SetValue(size_t(i), item);
            }
            out->SetList(list);
        } else {
            CefRefPtr<CefDictionaryValue> object = CefDictionaryValue::Create();
            std::vector<CefString> keys;
            v->GetKeys(keys);
            for (const CefString &key : keys) {
                if (!done)
                    break;
                CefRefPtr<CefValue> item = CefValue::Create();
                done = plain(v->GetValue(key), path, budget, item);
                object->SetValue(key, item);
            }
            out->SetDictionary(object);
        }
        path.pop_back();
        return done;
    }
    else
        out->SetNull();
    return true;
}

// The native route (~/book4-edge/opsis-beat-chrome-plan.md, stage 1): Opsis's scripts go into every new document from
// here, as each document's main world is made, and Opsis's own world is made beside it; runJavaScript evaluates here.
// No DevTools session: its Page domain cost ~0.6 on Speedometer (2026-10-08). The scripts come with the page
// (CreateBrowser's extra info, given to every page process the page uses) and, when they change, as "opsis.scripts".
class PageProcess : public CefApp, public CefRenderProcessHandler {
public:
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
    // browser:// as the browser process registers it (runtime.cpp): every process must know a custom scheme alike
    void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
        registrar->AddCustomScheme("browser", CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE | CEF_SCHEME_OPTION_LOCAL);
    }

    void OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> info) override {
        take(browser->GetIdentifier(), info);
    }
    void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override {
        m_pages.erase(browser->GetIdentifier());
        m_reported.erase(browser->GetIdentifier());
    }

    // The engine tells of two worlds only, the main one and Opsis's: a context this process asked for is Opsis's.
    void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) override {
        // Once per page in this process, from its main frame (OnBrowserCreated comes before the frame exists): the browser
        // numbers page processes by renderer-client-id, and this process's own pid is the sandbox's
        if (frame->IsMain() && m_reported.insert(browser->GetIdentifier()).second) {
            CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("opsis.process");
            message->GetArgumentList()->SetString(0, CefCommandLine::GetGlobalCommandLine()->GetSwitchValue("renderer-client-id"));
            frame->SendProcessMessage(PID_BROWSER, message);
        }
        if (!opsisWorld())
            return;
        const std::string id = frame->GetIdentifier().ToString();
        if (m_making.erase(id)) {
            m_worlds[id] = context;
            context->GetGlobal()->SetValue("__opsis", CefV8Value::CreateFunction("__opsis", new Bridge()),
                                           cef_v8_propertyattribute_t(V8_PROPERTY_ATTRIBUTE_READONLY | V8_PROPERTY_ATTRIBUTE_DONTENUM
                                                                      | V8_PROPERTY_ATTRIBUTE_DONTDELETE));
            return;
        }
        // a new document: Opsis's print(), then its scripts, in their order; Opsis's world is made with the first of its own
        context->GetGlobal()->SetValue("print", CefV8Value::CreateFunction("print", new Print()), V8_PROPERTY_ATTRIBUTE_NONE);
        m_mains.insert(id);
        m_worlds.erase(id);
        std::set<std::string> &ran = m_ran[id];
        ran.clear();
        for (const Script &s : m_pages[browser->GetIdentifier()].scripts) {
            ran.insert(s.key);
            run(frame, s);
        }
    }
    void OnContextReleased(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) override {
        if (!opsisWorld())
            return;
        const std::string id = frame->GetIdentifier().ToString();
        const auto world = m_worlds.find(id);
        if (world != m_worlds.end() && world->second->IsSame(context)) {
            m_worlds.erase(world);
            return;
        }
        m_mains.erase(id);
        m_making.erase(id);
        m_ran.erase(id);
    }

    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId,
                                  CefRefPtr<CefProcessMessage> message) override {
        const std::string name = message->GetName().ToString();
        CefRefPtr<CefListValue> arguments = message->GetArgumentList();
        if (!opsisWorld() || !frame || !arguments)
            return false;
        if (name == "opsis.scripts") {
            update(browser, frame, arguments->GetDictionary(0));
            return true;
        }
        if (name == "opsis.eval") {
            evaluate(frame, arguments->GetInt(0), arguments->GetString(1), arguments->GetBool(2));
            return true;
        }
        return false;
    }

private:
    struct Page {
        int generation = -1;
        std::vector<Script> scripts;
    };

    void take(int browser, CefRefPtr<CefDictionaryValue> info) {
        if (!info || !info->HasKey("scripts"))
            return;
        Page &page = m_pages[browser];
        page.generation = info->GetInt("generation");
        page.scripts.clear();
        CefRefPtr<CefListValue> list = info->GetList("scripts");
        for (size_t i = 0; list && i < list->GetSize(); ++i) {
            CefRefPtr<CefDictionaryValue> s = list->GetDictionary(i);
            if (s)
                page.scripts.push_back({s->GetString("key").ToString(), s->GetString("source").ToString(), s->GetBool("opsis")});
        }
    }
    // the page's scripts changed: those new to this frame's document run in it now, as DevTools' runImmediately did
    void update(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefDictionaryValue> info) {
        if (!info)
            return;
        const int page = browser->GetIdentifier();
        if (info->GetInt("generation") > m_pages[page].generation)
            take(page, info);
        const std::string id = frame->GetIdentifier().ToString();
        if (!m_mains.count(id))
            return;     // no document yet: it runs them all when it has one
        std::set<std::string> &ran = m_ran[id];
        std::set<std::string> now;
        for (const Script &s : m_pages[page].scripts) {
            now.insert(s.key);
            if (!ran.count(s.key))
                run(frame, s);
        }
        ran.swap(now);
    }
    void run(CefRefPtr<CefFrame> frame, const Script &s) {
        if (!s.opsis) {
            frame->ExecuteJavaScript(s.source, "", 0);
            return;
        }
        // the engine runs an "opsis-world:" script in Opsis's world, made by the first (OnContextCreated hears of it
        // before the script runs, so __opsis is there for it)
        const std::string id = frame->GetIdentifier().ToString();
        if (!m_worlds.count(id))
            m_making.insert(id);
        frame->ExecuteJavaScript(s.source, "opsis-world:" + s.key, 0);
    }
    CefRefPtr<CefV8Context> world(CefRefPtr<CefFrame> frame) {
        const std::string id = frame->GetIdentifier().ToString();
        if (!m_mains.count(id))
            frame->GetV8Context();      // the document's main world first: with it come its scripts and Opsis's world
        if (!m_worlds.count(id) && m_mains.count(id)) {
            m_making.insert(id);
            frame->ExecuteJavaScript("", "opsis-world:", 0);
        }
        const auto world = m_worlds.find(id);
        return world == m_worlds.end() ? nullptr : world->second;
    }
    // runJavaScript (PageClient::evaluateNow): the answer goes back as JSON text, none for undefined
    void evaluate(CefRefPtr<CefFrame> frame, int call, const CefString &script, bool inOpsisWorld) {
        CefRefPtr<CefProcessMessage> reply = CefProcessMessage::Create("opsis.evaled");
        CefRefPtr<CefListValue> answer = reply->GetArgumentList();
        answer->SetInt(0, call);
        answer->SetBool(1, false);
        CefRefPtr<CefV8Context> context = inOpsisWorld ? world(frame) : frame->GetV8Context();
        if (context && context->IsValid() && context->Enter()) {
            CefRefPtr<CefV8Value> value;
            CefRefPtr<CefV8Exception> exception;
            if (context->Eval(script, "", 0, value, exception)) {
                answer->SetBool(1, true);
                if (value && !value->IsUndefined()) {
                    std::vector<CefRefPtr<CefV8Value>> path;
                    int budget = 100000;
                    CefRefPtr<CefValue> out = CefValue::Create();
                    if (plain(value, path, budget, out))
                        answer->SetString(2, CefWriteJSON(out, JSON_WRITER_DEFAULT));
                    else
                        answer->SetBool(1, false);
                }
            }
            context->Exit();
        }
        frame->SendProcessMessage(PID_BROWSER, reply);
    }

    std::map<int, Page> m_pages;                                    // by browser
    std::set<int> m_reported;                                       // pages whose process id the browser was told
    // by frame (this process's), for its current document
    std::set<std::string> m_mains;                                  // its main world is made
    std::set<std::string> m_making;                                 // Opsis's world asked for, not made yet
    std::map<std::string, CefRefPtr<CefV8Context>> m_worlds;        // Opsis's world
    std::map<std::string, std::set<std::string>> m_ran;             // the keys of the scripts it has run

    IMPLEMENT_REFCOUNTING(PageProcess);
};

}   // namespace

// Chromium gives each process forked from its zygote a new stack canary, so a function that was on the stack at the
// fork must not check its own when it returns ("stack smashing detected" as the process ends).
NO_STACK_PROTECTOR
int main(int argc, char *argv[]) {
    // Tacit's text standard (book4-edge/tacit-text-plan.md): Skia here (the page and graphics processes) blends glyph
    // edges with TACIT_TEXT_GAMMA and TACIT_TEXT_CONTRAST (the Skia patch in Opsis's CEF build). Opsis sets them, and a
    // session may; where Chromium starts a process without them, the owner's pick of 2026-10-02.
    setenv("TACIT_TEXT_GAMMA", "2.2", 0);
    CefRefPtr<PageProcess> app = new PageProcess();
    return CefExecuteProcess(CefMainArgs(argc, argv), app, nullptr);
}
