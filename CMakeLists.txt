cmake_minimum_required(VERSION 3.21)
# Opsis's version, as Settings > About names it
project(browser VERSION 0.1 LANGUAGES CXX)

# The engine (book4-edge/opsis-cef-port-plan.md): Qt WebEngine, or CEF in a build dir of its own (build-cef) until the
# checks pass on it. With cef, `browser` is built on src/cef (BROWSER_CEF in the sources) and its QML goes in as source.
set(BROWSER_ENGINE "qt" CACHE STRING "qt or cef")
if(BROWSER_ENGINE STREQUAL "cef")
    set(BROWSER_CEF ON)
endif()

if(BROWSER_CEF)
    # WebSockets: DevTools' relay (src/cef/devtoolsbridge.*)
    find_package(Qt6 6.9 REQUIRED COMPONENTS Gui Qml Quick Network WebSockets ShaderTools DBus Pdf PdfQuick)
else()
    find_package(Qt6 6.9 REQUIRED COMPONENTS Gui Qml Quick WebEngineQuick WebEngineCore Network ShaderTools DBus Pdf PdfQuick)
endif()
# print (PLAN.md 3.16): the printers and a job sent to one go through libcups (src/printing.*)
find_package(Cups REQUIRED)
# Import from Zen (PLAN.md 3.4, 3.15): a copy of its places.sqlite read with SQLite (src/zen.*); NSS is loaded at run time
find_package(SQLite3 REQUIRED)
# Chrome's saved passwords and cookies (AES-128-CBC, PBKDF2: src/chromeimport.cpp)
find_package(OpenSSL REQUIRED COMPONENTS Crypto)
find_package(ZLIB REQUIRED)
# QWindowSystemInterface, for --check-engine to deliver keys as the window system does; QQuickWebEngineView's
# private header, for Windows.restore and Printing.toPdf (src/viewprivate.h)
set(QT_NO_PRIVATE_MODULE_WARNING ON)
if(BROWSER_CEF)
    find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)
else()
    find_package(Qt6 REQUIRED COMPONENTS GuiPrivate WebEngineQuickPrivate)
endif()
qt_standard_project_setup(REQUIRES 6.9)

# Brave's adblock engine behind a small C interface (adblock/src/lib.rs), built by cargo.
set(ADBLOCK_LIB ${CMAKE_CURRENT_SOURCE_DIR}/adblock/target/release/libadblockffi.a)
add_custom_command(
    OUTPUT ${ADBLOCK_LIB}
    COMMAND cargo build --release --quiet
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/adblock
    DEPENDS adblock/src/lib.rs adblock/Cargo.toml
    COMMENT "Building adblock engine")
add_custom_target(adblockffi DEPENDS ${ADBLOCK_LIB})

qt_add_executable(browser src/main.cpp src/glide.cpp src/glide.h src/adblock.cpp src/adblock.h src/shots.cpp src/shots.h src/enginecheck.cpp src/enginecheck.h src/instance.cpp src/instance.h src/notch.cpp src/notch.h src/viewprivate.h)
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
add_dependencies(browser adblockffi)
target_include_directories(browser PRIVATE src)
target_compile_definitions(browser PRIVATE OPSIS_VERSION="${PROJECT_VERSION}")
# build-dev (-DBROWSER_DEV=ON, what tools/ build): the QML goes in as source and is compiled when it loads, so a
# QML edit only re-embeds the files (about 1 s); build/ compiles each file to C++ with qmlcachegen (3-47 s).
option(BROWSER_DEV "QML as source, not compiled to C++ (build-dev)" OFF)
if(BROWSER_DEV OR BROWSER_CEF)
    set(qml_compile NO_CACHEGEN)
endif()
qt_add_qml_module(browser URI Browser ${qml_compile}
    SOURCES src/theme.cpp src/theme.h src/store.cpp src/store.h src/backdrop.cpp src/backdrop.h src/apps.cpp src/apps.h src/picker.cpp src/picker.h src/facts.cpp src/facts.h src/disk.cpp src/disk.h src/sitedata.cpp src/sitedata.h src/windows.cpp src/windows.h src/engine.cpp src/engine.h src/passwords.cpp src/passwords.h src/printing.cpp src/printing.h src/readability.cpp src/readability.h src/zen.cpp src/zen.h src/passwordfile.cpp src/passwordfile.h src/chromeimport.cpp src/chromeimport.h src/extensions.cpp src/extensions.h src/crx.cpp src/crx.h src/storerules.cpp src/storerules.h src/storefetch.cpp src/storefetch.h src/webstore.cpp src/webstore.h
    QML_FILES qml/Main.qml qml/BrowserView.qml qml/Session.qml qml/History.qml qml/Rail.qml qml/TabStrip.qml qml/Omnibox.qml qml/AddressField.qml qml/AddressEditor.qml qml/CommandBar.qml qml/SuggestionRow.qml qml/KeyCap.qml qml/IconButton.qml
              qml/RailRows.js qml/PageMenu.js qml/PageState.js qml/LoadLine.qml qml/Busy.qml qml/Count.qml qml/RowMenu.qml qml/KeyMap.js qml/Lifecycle.js
              qml/Asks.js qml/AskSection.qml qml/AskSheet.qml qml/Sites.qml qml/TextButton.qml qml/Slab.qml qml/PageDialog.qml qml/PopupCard.qml
              qml/Logins.js qml/DevTools.js qml/Swipe.js
              qml/Failures.js qml/FailurePage.qml qml/Welcome.qml
              qml/Find.js qml/Finder.qml qml/FindCard.qml
              qml/Downloads.js qml/Downloader.qml
              qml/Site.js qml/SiteInfo.qml qml/SitePanel.qml
              qml/Recall.js qml/Saved.qml qml/Marked.qml qml/JumpFoot.qml
              qml/NotchAddress.qml qml/NotchSignin.qml
              qml/Prefs.qml qml/Settings.js qml/Processes.js qml/OwnPage.qml qml/OwnHit.qml qml/SettingsPage.qml qml/SettingsRail.qml qml/Cove.qml qml/PagesPage.qml
              qml/Reader.js qml/Print.js qml/PrintCard.qml
              qml/Shots.qml qml/PageStandIn.qml qml/EngineCheck.qml
              qml/Theme.qml qml/Label.qml qml/Symbol.qml qml/ThinScrollBar.qml qml/Frost.qml qml/PageScrollBar.qml qml/SectionStrip.qml
              qml/Anim.qml qml/CAnim.qml qml/TacitSymbolNames.js
    # Tacit's own symbols (~/dev/tacit-icons build), as the shell draws them
    RESOURCES assets/fonts/TacitSymbols.ttf assets/fonts/TacitSymbolsFill.ttf)
qt_add_shaders(browser "shaders" QUIET PREFIX "/qt/qml/Browser" FILES shaders/frost.frag)
# Reader view (PLAN.md 3.9): Mozilla's Readability.js, unmodified (readability/LICENSE.md), for src/readability.*
qt_add_resources(browser "readability" PREFIX "/readability" BASE readability FILES readability/Readability.js readability/Readability-readerable.js)
# the reader checks' saved pages (tools/check-engine reader), for EngineCheck::savedPage
qt_add_resources(browser "savedpages" PREFIX "/check" BASE tests/fixtures
                 FILES tests/fixtures/reader/lwn.html tests/fixtures/reader/news.html tests/fixtures/reader/github.html)
if(BROWSER_CEF)
    target_link_libraries(browser PRIVATE
        Qt6::Gui Qt6::GuiPrivate Qt6::Network Qt6::Qml Qt6::Quick Qt6::DBus
        Qt6::Pdf Qt6::PdfQuick Cups::Cups SQLite3::SQLite3 OpenSSL::Crypto ZLIB::ZLIB
        ${ADBLOCK_LIB} dl pthread m)
    # the cef library, PageItem and CefRuntime, the stand-in for Qt WebEngine's QML module, browser-page and cefpage
    add_subdirectory(src/cef)
else()
target_link_libraries(browser PRIVATE
    Qt6::Gui Qt6::GuiPrivate Qt6::WebEngineQuickPrivate Qt6::Network Qt6::Qml Qt6::Quick Qt6::WebEngineQuick Qt6::WebEngineCore Qt6::DBus
    Qt6::Pdf Qt6::PdfQuick Cups::Cups SQLite3::SQLite3 OpenSSL::Crypto ZLIB::ZLIB
    ${ADBLOCK_LIB} dl pthread m)
endif()

install(TARGETS browser)

# The Chrome Web Store feature's parts that need no window or network (src/crx.*, src/storerules.*): ctest, or
# `cmake --build <dir> --target store_test` and run <dir>/store_test
find_package(Qt6 REQUIRED COMPONENTS Test)
enable_testing()
qt_add_executable(store_test EXCLUDE_FROM_ALL tests/native/store_test.cpp src/crx.cpp src/storerules.cpp src/storefetch.cpp src/webstore.cpp src/extensions.cpp)
target_include_directories(store_test PRIVATE src)
target_compile_definitions(store_test PRIVATE SRCDIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/native")
target_link_libraries(store_test PRIVATE Qt6::Core Qt6::Qml Qt6::Network Qt6::Test OpenSSL::Crypto ZLIB::ZLIB)
add_test(NAME store_test COMMAND store_test)
