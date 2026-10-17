import QtQuick
import QtTest
import "../qml/PageState.js" as PageState

// PageState.js: https-first, Not secure, the card's second line, and the page's dialogs, popups, file picks,
// drops and full screen (PLAN.md 3.8).
TestCase {
    name: "PageState"

    function test_hostOf() {
        compare(PageState.hostOf("https://www.GitHub.com/linux-msm"), "www.github.com");
        compare(PageState.hostOf("http://bank.com:x@evil.example:8080/"), "evil.example", "user:pass@ is not the host");
        compare(PageState.hostOf("http://[::1]:8080/x"), "[::1]");
        compare(PageState.hostOf("about:blank"), "");
    }

    function test_sameSite() {
        verify(PageState.sameSite("https://claude.ai/new", "https://claude.ai/login/callback?code=1"), "the same host");
        verify(PageState.sameSite("https://a.claude.ai/x", "https://claude.ai/"), "one host under the other");
        verify(PageState.sameSite("https://shop.example/", "https://www.shop.example/done"));
        verify(!PageState.sameSite("https://accounts.google.com/o/oauth2", "https://claude.ai/"), "another site");
        verify(!PageState.sameSite("https://a.co.uk/", "https://b.co.uk/"), "siblings under a public suffix");
        verify(!PageState.sameSite("https://notclaude.ai/", "https://claude.ai/"), "a name that only ends the same");
        verify(!PageState.sameSite("about:blank", "https://claude.ai/"), "no host");
        verify(PageState.sameSite("http://127.0.0.1:8080/a", "http://127.0.0.1:9090/b"), "the port is not the site");
    }

    function test_httpsFirst_data() {
        return [
            { tag: "scheme-less", text: "neverssl.com", url: "https://neverssl.com",
              first: "https://neverssl.com", fallback: "http://neverssl.com" },
            { tag: "scheme-less with path and port", text: "plain.test:8123/login", url: "https://plain.test:8123/login",
              first: "https://plain.test:8123/login", fallback: "http://plain.test:8123/login" },
            { tag: "typed http://", text: "http://neverssl.com/online", url: "http://neverssl.com/online",
              first: "https://neverssl.com/online", fallback: "http://neverssl.com/online" },
            { tag: "typed https:// has no fallback", text: "https://expired.badssl.com", url: "https://expired.badssl.com",
              first: "https://expired.badssl.com", fallback: "" },
            { tag: "localhost", text: "localhost:8080", url: "http://localhost:8080", first: "http://localhost:8080", fallback: "" },
            { tag: "a .localhost name", text: "http://app.localhost/", url: "http://app.localhost/", first: "http://app.localhost/", fallback: "" },
            { tag: "IPv4 on the LAN", text: "192.168.1.1/admin", url: "http://192.168.1.1/admin", first: "http://192.168.1.1/admin", fallback: "" },
            { tag: "IPv6", text: "http://[fe80::1]/", url: "http://[fe80::1]/", first: "http://[fe80::1]/", fallback: "" },
            { tag: "a LAN name is tried", text: "http://router.lan", url: "http://router.lan", first: "https://router.lan", fallback: "http://router.lan" },
            { tag: "other schemes", text: "about:blank", url: "about:blank", first: "about:blank", fallback: "" },
            { tag: "file", text: "file:///home/abdul/x.pdf", url: "file:///home/abdul/x.pdf", first: "file:///home/abdul/x.pdf", fallback: "" },
        ];
    }
    function test_httpsFirst(data) {
        const r = PageState.httpsFirst(data.text, data.url);
        compare(r.url, data.first);
        compare(r.fallback, data.fallback);
    }

    function test_insecure() {
        verify(PageState.insecure("http://neverssl.com/online"));
        verify(PageState.insecure("HTTP://neverssl.com/"));
        verify(PageState.insecure("http://192.168.1.1/"), "the LAN is a network");
        verify(!PageState.insecure("https://github.com/"), "a normal https page shows no lock and no warning");
        verify(!PageState.insecure("http://localhost:8080/"), "this machine");
        verify(!PageState.insecure("http://127.0.0.1:5000/"));
        verify(!PageState.insecure("http://[::1]/"));
        verify(!PageState.insecure("http://app.localhost/"));
        verify(PageState.insecure("http://localhost.evil.example/"), "a name that only starts like localhost");
        verify(!PageState.insecure("about:blank"));
        verify(!PageState.insecure("data:text/html,x"));
    }

    function test_dialogNamesTheTopFramesHost() {
        compare(PageState.says("https://www.github.com/linux-msm/linux/issues/212"), "github.com says");
        compare(PageState.says("http://127.0.0.1:8123/dialogs"), "127.0.0.1:8123 says", "the port stays, as in the card");
        compare(PageState.says("https://bank.example:x@evil.example/"), "evil.example says", "user:pass@ is not the host");
        compare(PageState.says("data:text/html,<script>alert(1)</script>"), "This page says", "a data: URL never shows its content");
        compare(PageState.says("about:blank"), "This page says");
        compare(PageState.says("file:///home/abdul/x.html"), "This page says");
        compare(PageState.blockMore("https://github.com/x"), "Block more dialogs from github.com");
        compare(PageState.blockMore("data:text/html,x"), "Block more dialogs from this page");
    }

    function test_stateLine() {
        compare(PageState.stateLine({ waitingFor: "" }), "");
        compare(PageState.stateLine({ waitingFor: "lwn.net" }), "Waiting for lwn.net");
        compare(PageState.stateLine({ popup: true, waitingFor: "lwn.net" }), "Sign-in window open");
        compare(PageState.stateLine({ popup: true, choosing: true }), "Choosing files in Files");
        compare(PageState.stateLine({ dialog: true, choosing: true, popup: true, waitingFor: "lwn.net" }), "Dialog from this page",
                "a dialog holds the page: it comes first");
        compare(PageState.stateLine({ failure: "Certificate expired", waitingFor: "expired.badssl.com" }), "Certificate expired",
                "a certificate's page holds the load: no Waiting for");
    }

    function test_newWindow_data() {
        return [
            { tag: "window.open with a size", destination: "dialog", user: true, url: "https://accounts.example/o", where: "popup" },
            { tag: "window.open without a size", destination: "tab", user: true, url: "https://example.com/", where: "page" },
            { tag: "without a size, to a sign-in host", destination: "tab", user: true, url: "https://accounts.google.com/o/oauth2/auth", where: "popup" },
            { tag: "to PayPal", destination: "tab", user: true, url: "https://www.paypal.com/checkoutnow", where: "popup" },
            { tag: "to a bank's 3-D Secure host", destination: "tab", user: true, url: "https://3ds.handelsbanken.se/verify", where: "popup" },
            { tag: "a host that only contains 3ds", destination: "tab", user: true, url: "https://my3ds.example/", where: "page" },
            { tag: "middle-click to a sign-in host stays a row", destination: "background", user: true, url: "https://accounts.google.com/", where: "page" },
            { tag: "shift-click", destination: "window", user: true, url: "https://example.com/", where: "page" },
            { tag: "no click from you", destination: "dialog", user: false, url: "https://ads.example/", where: "blocked" },
            { tag: "no click, no size", destination: "tab", user: false, url: "https://example.com/", where: "blocked" },
        ];
    }
    function test_newWindow(data) {
        compare(PageState.newWindow(data.destination, data.user, data.url), data.where);
    }

    function test_appSignIn_data() {
        return [
            { tag: "gcloud's Google authorize", url: "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=32555940559.apps.googleusercontent.com&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F&scope=openid", is: true },
            { tag: "Google's sign-in page", url: "https://accounts.google.com/v3/signin/identifier?continue=x", is: true },
            { tag: "Google account settings", url: "https://accounts.google.com/ManageAccount", is: false },
            { tag: "Microsoft", url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?x=1", is: true },
            { tag: "GitHub's device code", url: "https://github.com/login/device", is: true },
            { tag: "GitHub's authorize", url: "https://github.com/login/oauth/authorize?client_id=a", is: true },
            { tag: "a GitHub repository", url: "https://github.com/linux-msm/linux", is: false },
            { tag: "Apple", url: "https://appleid.apple.com/auth/authorize?client_id=a", is: true },
            { tag: "any OAuth authorize", url: "https://auth.example.com/authorize?response_type=code&client_id=a&redirect_uri=http://127.0.0.1:9000/cb", is: true },
            { tag: "a link with only a client_id", url: "https://example.com/docs?client_id=a", is: false },
            { tag: "a bank's 3-D Secure host", url: "https://3ds.handelsbanken.se/verify", is: true },
            { tag: "a normal page", url: "https://lore.kernel.org/linux-media/", is: false },
            { tag: "PayPal is no sign-in from an app", url: "https://www.paypal.com/", is: false },
            { tag: "Tailscale's login host", url: "https://login.tailscale.com/a/1a2b3c4d", is: true },
            { tag: "OpenAI's auth host", url: "https://auth.openai.com/log-in", is: true },
            { tag: "a site's own login page", url: "https://www.notion.so/login", is: true },
            { tag: "a login under a path", url: "https://huggingface.co/en/signin/", is: true },
            { tag: "Microsoft's device code page", url: "https://microsoft.com/devicelogin", is: true },
            { tag: "single sign-on", url: "https://example.okta.com/app/x/sso", is: true },
            { tag: "docs about OAuth stay a page", url: "https://docs.rs/oauth2/latest/oauth2/", is: false },
            { tag: "a file named login.go stays a page", url: "https://github.com/a/b/blob/main/auth/login.go", is: false },
            { tag: "a blog post about logins stays a page", url: "https://example.com/blog/how-to-login-faster", is: false },
            { tag: "an author page is no auth", url: "https://example.com/authors/jane", is: false },
        ];
    }
    function test_appSignIn(data) {
        compare(PageState.appSignIn(data.url), data.is);
    }
    function test_redirect() {
        const link = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=a&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F";
        compare(PageState.redirectOf(link), "http://localhost:8085/");
        compare(PageState.redirectOf("https://example.com/?redirect_uri=javascript:alert(1)"), "", "only a web address");
        verify(PageState.reached("http://localhost:8085/?state=s&code=4/0A", "http://localhost:8085/"), "the loopback callback");
        verify(PageState.reached("http://127.0.0.1:8085/?code=1", "http://localhost:8085/"), "any loopback name");
        verify(!PageState.reached("http://localhost:9999/?code=1", "http://localhost:8085/"), "another port");
        verify(PageState.reached("https://app.example/oauth/callback?code=1", "https://app.example/oauth/callback"), "the redirect host and path");
        verify(!PageState.reached("https://app.example/oauth/callbacks", "https://app.example/oauth/callback"), "a path that only starts the same");
        verify(!PageState.reached("https://auth.example.com/authorize?response_type=code&client_id=a&redirect_uri=https://auth.example.com/",
                                  "https://auth.example.com/"), "the authorize page on the redirect's own host");
        verify(!PageState.reached("https://cloud.google.com/sdk/auth_success", "http://localhost:8085/"), "elsewhere");
        verify(!PageState.reached("http://localhost:8085/", ""), "no redirect named");
    }

    function test_pick() {
        compare(PageState.pickLabel("multiple", "github.com"), "Choose files for github.com");
        compare(PageState.pickLabel("one", "github.com"), "Choose files for github.com");
        compare(PageState.pickLabel("folder", "github.com"), "Choose a folder for github.com");
        compare(PageState.pickLabel("one", ""), "Choose files for this page");
        compare(PageState.pickedFor("multiple", ["/a", "/b"]), ["/a", "/b"]);
        compare(PageState.pickedFor("one", ["/a", "/b"]), ["/a"], "an input without multiple takes one file");
        compare(PageState.pickedFor("folder", ["/d"]), ["/d"]);
        compare(PageState.pickedFor("one", []), [], "nothing chosen: nothing changes");
    }

    function test_dropped_data() {
        return [
            { tag: "a text file on a web page", target: "file:///home/abdul/notes.txt", current: "https://github.com/x", out: "page" },
            { tag: "a PDF", target: "file:///home/abdul/S2MM006.PDF", current: "https://github.com/x", out: "page" },
            { tag: "an image", target: "file:///tmp/shot.png", current: "http://127.0.0.1:8123/drop", out: "page" },
            { tag: "any other file does nothing", target: "file:///home/abdul/camss.zip", current: "https://github.com/x", out: "nothing" },
            { tag: "a file without a type", target: "file:///home/abdul/Makefile", current: "https://github.com/x", out: "nothing" },
            { tag: "a file page's own links", target: "file:///home/abdul/b.txt", current: "file:///home/abdul/a.html", out: "" },
            { tag: "a page not loaded yet", target: "file:///home/abdul/notes.txt", current: "", out: "" },
            { tag: "a web address", target: "https://github.com/y", current: "https://github.com/x", out: "" },
        ];
    }
    function test_dropped(data) {
        compare(PageState.dropped(data.target, data.current), data.out);
    }

    function test_fullScreenNotices() {
        compare(PageState.fullScreenNotice, "Esc exits full screen");
        compare(PageState.askingNotice("meet.google.com"), "meet.google.com is asking · Esc to answer");
    }
}
