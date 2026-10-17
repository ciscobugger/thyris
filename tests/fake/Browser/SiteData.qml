pragma Singleton
import QtQuick

// Stand-in for the C++ SiteData (src/sitedata.h): cookies per host, and what was cleared.
QtObject {
    property int revision: 0
    property var counts: ({})
    property var cleared: []
    function cookies(host) { return counts[host] ?? 0 }
    function clearCookies(host) { cleared = cleared.concat([host]); const n = counts[host] ?? 0; counts[host] = 0; revision++; return n }
}
