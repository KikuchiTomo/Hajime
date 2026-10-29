# はじめの Fcitx 5 のアドオン(docs/dev/adr/0012-linux.md)．
# C++ の薄い口(src/)と，エンジンと話す Rust の橋渡し(bridge/．静的ライブラリ)を 1 つのモジュールにする．
#   cmake -S apps/linux/fcitx5 -B build && cmake --build build && cmake --install build
cmake_minimum_required(VERSION 3.16)
project(hajime-fcitx5 VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)

find_package(Fcitx5Core 5.0 REQUIRED)

# エンジン(hajime-engine-host)を置く場所．アドオンは，エンジンが動いていなければここから起こす
set(HAJIME_ENGINE_PATH "${CMAKE_INSTALL_FULL_LIBEXECDIR}/haji.men/hajime-engine-host" CACHE FILEPATH "エンジンの実行ファイル")

# Fcitx 5 の決まった置き場所．古い Fcitx 5 の CMake の設定に無いときは，distro の標準の場所にする
if(NOT DEFINED FCITX_INSTALL_ADDONDIR)
    set(FCITX_INSTALL_ADDONDIR "${CMAKE_INSTALL_LIBDIR}/fcitx5")
endif()
if(NOT DEFINED FCITX_INSTALL_PKGDATADIR)
    set(FCITX_INSTALL_PKGDATADIR "${CMAKE_INSTALL_DATADIR}/fcitx5")
endif()

# Rust の橋渡し．版は bridge/rust-toolchain.toml，依存は bridge/Cargo.lock で固定する
set(HAJIME_BRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bridge")
set(HAJIME_BRIDGE_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/bridge")
set(HAJIME_BRIDGE_LIBRARY "${HAJIME_BRIDGE_TARGET_DIR}/release/libhajime_fcitx5_bridge.a")
file(GLOB_RECURSE HAJIME_BRIDGE_SOURCES CONFIGURE_DEPENDS
    "${HAJIME_BRIDGE_DIR}/src/*.rs"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/crates/ipc/src/*.rs")
add_custom_command(
    OUTPUT "${HAJIME_BRIDGE_LIBRARY}"
    COMMAND cargo build --release --locked --manifest-path "${HAJIME_BRIDGE_DIR}/Cargo.toml" --target-dir "${HAJIME_BRIDGE_TARGET_DIR}"
    WORKING_DIRECTORY "${HAJIME_BRIDGE_DIR}"
    DEPENDS ${HAJIME_BRIDGE_SOURCES} "${HAJIME_BRIDGE_DIR}/Cargo.toml" "${HAJIME_BRIDGE_DIR}/Cargo.lock"
    COMMENT "Rust の橋渡しをビルドする"
    USES_TERMINAL)
add_custom_target(hajime-bridge-build DEPENDS "${HAJIME_BRIDGE_LIBRARY}")
add_library(hajime-bridge STATIC IMPORTED)
set_target_properties(hajime-bridge PROPERTIES IMPORTED_LOCATION "${HAJIME_BRIDGE_LIBRARY}")
add_dependencies(hajime-bridge hajime-bridge-build)

find_package(Threads REQUIRED)
add_library(hajime MODULE src/engine.cpp)
set_target_properties(hajime PROPERTIES PREFIX "")
target_include_directories(hajime PRIVATE "${HAJIME_BRIDGE_DIR}/include")
target_compile_definitions(hajime PRIVATE HAJIME_ENGINE_PATH="${HAJIME_ENGINE_PATH}")
target_compile_options(hajime PRIVATE -Wall -Wextra)
# Rust の静的ライブラリが使う C の標準ライブラリの部品
target_link_libraries(hajime PRIVATE Fcitx5::Core hajime-bridge Threads::Threads ${CMAKE_DL_LIBS} m)

install(TARGETS hajime DESTINATION "${FCITX_INSTALL_ADDONDIR}")
install(FILES conf/addon.conf RENAME hajime.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon")
install(FILES conf/inputmethod.conf RENAME hajime.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod")
