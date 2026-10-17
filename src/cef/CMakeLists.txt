# The CEF engine, beside Qt WebEngine until Opsis's checks pass on it (book4-edge/opsis-cef-port-plan.md): CEF's start
# and stop (CefRuntime), the page view (PageItem), the stand-in for Qt WebEngine's QML module that Opsis's QML imports
# (shim/QtWebEngine), the page processes' executable (browser-page) and a test window (cefpage, run by tools/cef-page).
set(CEF_ROOT "$ENV{HOME}/cef-spike/cef_binary_154.0.34+g14c5a08+chromium-154.0.8037.98_linuxarm64" CACHE PATH
    "CEF's standard distribution, the client distribution's data files copied beside Release/libcef.so")
set(CEF_WRAPPER ${CEF_ROOT}/build/libcef_dll_wrapper/libcef_dll_wrapper.a)
if(NOT EXISTS ${CEF_ROOT}/Release/libcef.so OR NOT EXISTS ${CEF_ROOT}/Release/icudtl.dat OR NOT EXISTS ${CEF_WRAPPER})
    message(FATAL_ERROR "CEF_ROOT (${CEF_ROOT}) needs Release/libcef.so, icudtl.dat beside it, and "
                        "build/libcef_dll_wrapper/libcef_dll_wrapper.a (cmake + ninja libcef_dll_wrapper in build/)")
endif()

add_library(cef INTERFACE)
target_include_directories(cef INTERFACE ${CEF_ROOT})
target_compile_definitions(cef INTERFACE WRAPPING_CEF_SHARED NDEBUG)
target_compile_features(cef INTERFACE cxx_std_20)
target_link_libraries(cef INTERFACE ${CEF_WRAPPER} ${CEF_ROOT}/Release/libcef.so ${CMAKE_DL_LIBS})

# the page processes (renderer, GPU, network): no Qt in them
add_executable(browser-page pageprocess.cpp)
target_link_libraries(browser-page PRIVATE cef)

qt_add_executable(cefpage cefpage.cpp runtime.cpp runtime.h pageitem.cpp pageitem.h input.cpp input.h scripts.cpp scripts.h requests.cpp requests.h
                  devtoolsbridge.cpp devtoolsbridge.h)
target_link_libraries(cefpage PRIVATE cef Qt6::Gui Qt6::Qml Qt6::Quick Qt6::WebSockets EGL)
target_compile_definitions(cefpage PRIVATE CEFPAGE_QML="${CMAKE_CURRENT_SOURCE_DIR}/CefPage.qml" OPSIS_VERSION="${PROJECT_VERSION}")
add_dependencies(cefpage browser-page)
set_target_properties(browser-page cefpage PROPERTIES
    BUILD_RPATH ${CEF_ROOT}/Release RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# `browser` on CEF
target_sources(browser PRIVATE runtime.cpp runtime.h pageitem.cpp pageitem.h input.cpp input.h scripts.cpp scripts.h requests.cpp requests.h
               devtoolsbridge.cpp devtoolsbridge.h)
target_compile_definitions(browser PRIVATE BROWSER_CEF)
target_link_libraries(browser PRIVATE cef Qt6::WebSockets EGL)
add_dependencies(browser browser-page)
set_target_properties(browser PROPERTIES BUILD_RPATH ${CEF_ROOT}/Release)
file(GLOB shim_files RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS shim/QtWebEngine/*)
qt_add_resources(browser "cefshim" PREFIX "/cefshim" BASE shim FILES ${shim_files})
