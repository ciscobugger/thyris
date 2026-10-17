pragma Singleton
import QtQuick

// Stand-in for the C++ Facts (src/facts.h): the TLS handshakes asked for; tests answer with tlsFound.
QtObject {
    property var asked: []
    signal tlsFound(string host, int port, var tls)
    function lookUpTls(host, port) { asked = asked.concat([host + ":" + port]) }
}
