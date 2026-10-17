import QtQml

// Qt WebEngine's WebEngineProfilePrototype for Opsis's QML on CEF (see WebEngineView.qml in this folder): instance()
// makes the one profile it describes.
QtObject {
    id: prototype
    property string storageName
    property string persistentStoragePath
    property int persistentPermissionsPolicy: WebEngineProfile.StoreOnDisk
    property var made: null
    property Component maker: Component { WebEngineProfile {} }
    function instance() {
        if (!made)
            made = maker.createObject(prototype, { storageName: storageName, persistentStoragePath: persistentStoragePath,
                                                   persistentPermissionsPolicy: persistentPermissionsPolicy });
        return made;
    }
}
