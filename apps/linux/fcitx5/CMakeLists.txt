# s90.tokyo IME の Fcitx 5 のアドオン(docs/dev/adr/0012-linux.md)．
# C++ の薄い口(src/)と，エンジンと話す Rust の橋渡し(bridge/．静的ライブラリ)を 1 つのモジュールにする．
#   cmake -S apps/linux/fcitx5 -B build && cmake --build build && cmake --install build
cmake_minimum_required(VERSION 3.16)
project(s90-fcitx5 VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)

find_package(Fcitx5Core 5.0 REQUIRED)

# エンジン(s90-engine-host)を置く場所．アドオンは，エンジンが動いていなければここから起こす
set(S90_ENGINE_PATH "${CMAKE_INSTALL_FULL_LIBEXECDIR}/s90.tokyo/s90-engine-host" CACHE FILEPATH "エンジンの実行ファイル")

# Fcitx 5 の決まった置き場所．古い Fcitx 5 の CMake の設定に無いときは，distro の標準の場所にする
if(NOT DEFINED FCITX_INSTALL_ADDONDIR)
    set(FCITX_INSTALL_ADDONDIR "${CMAKE_INSTALL_LIBDIR}/fcitx5")
endif()
if(NOT DEFINED FCITX_INSTALL_PKGDATADIR)
    set(FCITX_INSTALL_PKGDATADIR "${CMAKE_INSTALL_DATADIR}/fcitx5")
endif()

# Rust の橋渡し．版は bridge/rust-toolchain.toml，依存は bridge/Cargo.lock で固定する
set(S90_BRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bridge")
set(S90_BRIDGE_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/bridge")
set(S90_BRIDGE_LIBRARY "${S90_BRIDGE_TARGET_DIR}/release/libs90_fcitx5_bridge.a")
file(GLOB_RECURSE S90_BRIDGE_SOURCES CONFIGURE_DEPENDS
    "${S90_BRIDGE_DIR}/src/*.rs"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/crates/ipc/src/*.rs")
add_custom_command(
    OUTPUT "${S90_BRIDGE_LIBRARY}"
    COMMAND cargo build --release --locked --manifest-path "${S90_BRIDGE_DIR}/Cargo.toml" --target-dir "${S90_BRIDGE_TARGET_DIR}"
    WORKING_DIRECTORY "${S90_BRIDGE_DIR}"
    DEPENDS ${S90_BRIDGE_SOURCES} "${S90_BRIDGE_DIR}/Cargo.toml" "${S90_BRIDGE_DIR}/Cargo.lock"
    COMMENT "Rust の橋渡しをビルドする"
    USES_TERMINAL)
add_custom_target(s90-bridge-build DEPENDS "${S90_BRIDGE_LIBRARY}")
add_library(s90-bridge STATIC IMPORTED)
set_target_properties(s90-bridge PROPERTIES IMPORTED_LOCATION "${S90_BRIDGE_LIBRARY}")
add_dependencies(s90-bridge s90-bridge-build)

find_package(Threads REQUIRED)
add_library(s90 MODULE src/engine.cpp)
set_target_properties(s90 PROPERTIES PREFIX "")
target_include_directories(s90 PRIVATE "${S90_BRIDGE_DIR}/include")
target_compile_definitions(s90 PRIVATE S90_ENGINE_PATH="${S90_ENGINE_PATH}")
target_compile_options(s90 PRIVATE -Wall -Wextra)
# Rust の静的ライブラリが使う C の標準ライブラリの部品
target_link_libraries(s90 PRIVATE Fcitx5::Core s90-bridge Threads::Threads ${CMAKE_DL_LIBS} m)

install(TARGETS s90 DESTINATION "${FCITX_INSTALL_ADDONDIR}")
install(FILES conf/addon.conf RENAME s90.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon")
install(FILES conf/inputmethod.conf RENAME s90.conf DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod")
