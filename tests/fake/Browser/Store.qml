pragma Singleton
import QtQuick

// In-memory stand-in for the C++ Store (src/store.h) so the models run under qmltestrunner.
// Values are copied through JSON both ways, as the real one writes and reads JSON files.
QtObject {
    property string dataDir: ""
    property var files: ({})

    function load(name) { return name in files ? JSON.parse(files[name]) : undefined }
    function save(name, value) { files[name] = JSON.stringify(value); return true }
}
