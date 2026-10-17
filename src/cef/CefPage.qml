import QtQuick
import Browser.Cef

// The CEF page view's test window (tools/cef-page): the page, and over it a sheet of glass where the lifted rail lies
// in Opsis (12, 12, 282 wide, radius 12), to show the page is one more item of the scene.
Item {
    width: 1920
    height: 1080

    PageItem {
        id: page
        objectName: "page"
        anchors.fill: parent
        url: startUrl
    }
    Rectangle {
        x: 12
        y: 12
        width: 282
        height: parent.height - 24
        radius: 12
        color: "#b01e1b1a"
        border.color: "#12e8e1df"
        Text {
            x: 16
            y: 14
            width: parent.width - 32
            wrapMode: Text.Wrap
            color: "#efeae9"
            font.pixelSize: 14
            text: (page.loading ? "Loading" : "Loaded") + "\n" + page.title + "\n"
                  + (page.shared ? "frames on the graphics chip" : "frames through memory")
        }
    }
}
