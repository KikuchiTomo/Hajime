# Zenzai が使う llama.cpp の Windows 向けのビルドを，azooKey の llama.cpp(b9637-azookey.1)のソースから作る．
# 公式のビルドは zenz の語の分け方(gpt2-small-japanese-char)を知らず，zenz のモデルを読めない．そのため azooKey の改変を含むソースからビルドする．
# エンジン(core)の AzooKeyKanaKanjiConverter は Windows では llama.cpp をシステムのライブラリとして探すので，
# 出力の場所を LIB(リンク時の llama.lib・ggml.lib)と PATH(実行時の llama.dll・ggml*.dll)に足して使う．
# CPU の命令ごとに ggml-cpu-*.dll を作り，エンジンは llama.dll と同じ場所から合うものを実行時に選んで読む(GGML_BACKEND_DL)．
# OpenMP は使わない(ggml のスレッドプールを使い，OpenMP のランタイムを配らない)．
# 版を変えるときは，AzooKeyKanaKanjiConverter の Sources/llama.cpp のヘッダーと，macOS で使う xcframework の版を合わせる．
#
# 使い方: tools/windows/build_llama.ps1 -Output <出力の場所>
param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
# タグ b9637-azookey.1 のコミット(MIT．THIRD_PARTY_NOTICES.md の llama.cpp)
$repository = 'https://github.com/azooKey/llama.cpp'
$commit = '66afb885a8ddcc0511798aec9fb5a01017941018'

$work = Join-Path ([System.IO.Path]::GetTempPath()) "llama-$([guid]::NewGuid())"
$source = Join-Path $work 'source'
$build = Join-Path $work 'build'
New-Item -ItemType Directory -Force -Path $source | Out-Null
try {
    # タグは付け替えられるので，コミットの ID で取得し，取得したものがそのコミットかを確かめる
    git -C $source init --quiet
    git -C $source fetch --quiet --depth 1 $repository $commit
    if ($LASTEXITCODE -ne 0) { throw 'llama.cpp を取得できませんでした' }
    git -C $source checkout --quiet FETCH_HEAD
    $actual = (git -C $source rev-parse HEAD).Trim()
    if ($actual -ne $commit) { throw "llama.cpp のコミットが違います: $actual" }

    # Swift の toolchain の clang の場所(vcvars で PATH が変わる前に探す)
    $swift = Get-Command swift -ErrorAction SilentlyContinue
    $swiftLlvm = if ($swift) { Split-Path $swift.Source } else { $null }

    # Visual Studio の C++ の環境(リンカ・Windows SDK・CMake・Ninja)を読み込む
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual Studio の C++ のツールが見つかりません' }
    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2]) }
    }
    if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) { throw 'Ninja が見つかりません' }

    # ggml の CPU の処理は MSVC より clang のほうが速いので，clang でビルドする．
    # HAJIME_LLVM_BIN を指定すると，その場所の clang を使う．指定しなければ，Swift の toolchain の clang(Hajime IME のビルドに必ず入っていて，
    # 手元の PC と CI で同じ版になる)，無ければ Visual Studio に入っている clang を使う．
    # Visual Studio 18 の clang 22 では，CI のランナーでビルドの最後の手順が終わらなかった(2026-11-13)
    if ($env:HAJIME_LLVM_BIN) {
        $llvm = $env:HAJIME_LLVM_BIN
        if (-not (Test-Path (Join-Path $llvm 'clang.exe'))) { throw "HAJIME_LLVM_BIN に clang.exe がありません: $llvm" }
    } else {
        $llvm = @($swiftLlvm, (Join-Path $vs 'VC\Tools\Llvm\x64\bin'), (Join-Path $vs 'VC\Tools\Llvm\bin')) |
            Where-Object { $_ -and (Test-Path (Join-Path $_ 'clang.exe')) } | Select-Object -First 1
        if (-not $llvm) { throw 'clang が見つかりません(HAJIME_LLVM_BIN で clang の場所を指定できます)' }
    }
    Write-Host "clang: $llvm"
    $clang = (Join-Path $llvm 'clang.exe') -replace '\\', '/'
    $clangxx = (Join-Path $llvm 'clang++.exe') -replace '\\', '/'

    # Clang 22 は型の合わないポインタの受け渡しを既定で error にする．ggml の x86 の量子化のコードは _mm_prefetch に構造体のポインタを渡すので，
    # この警告だけを error にしない
    cmake -S $source -B $build -G Ninja `
        -DCMAKE_BUILD_TYPE=Release `
        "-DCMAKE_C_COMPILER=$clang" `
        "-DCMAKE_CXX_COMPILER=$clangxx" `
        "-DCMAKE_C_FLAGS=-Wno-error=incompatible-pointer-types" `
        -DBUILD_SHARED_LIBS=ON `
        -DGGML_NATIVE=OFF `
        -DGGML_BACKEND_DL=ON `
        -DGGML_CPU_ALL_VARIANTS=ON `
        -DGGML_OPENMP=OFF `
        -DGGML_RPC=OFF `
        -DLLAMA_BUILD_COMMON=OFF `
        -DLLAMA_BUILD_TESTS=OFF `
        -DLLAMA_BUILD_TOOLS=OFF `
        -DLLAMA_BUILD_EXAMPLES=OFF `
        -DLLAMA_BUILD_SERVER=OFF `
        -DLLAMA_BUILD_APP=OFF `
        -DLLAMA_BUILD_UI=OFF `
        -DLLAMA_OPENSSL=OFF
    if ($LASTEXITCODE -ne 0) { throw 'llama.cpp の構成に失敗しました' }
    cmake --build $build --config Release
    if ($LASTEXITCODE -ne 0) { throw 'llama.cpp のビルドに失敗しました' }

    New-Item -ItemType Directory -Force -Path $Output | Out-Null
    Get-ChildItem -Path (Join-Path $build 'bin') -File -Filter '*.dll' | Copy-Item -Destination $Output
    foreach ($library in @('llama.lib', 'ggml.lib', 'ggml-base.lib')) {
        $found = Get-ChildItem -Path $build -Recurse -File -Filter $library | Select-Object -First 1
        if (-not $found) { throw "$library がありません" }
        Copy-Item $found.FullName $Output
    }
} finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $work
}
foreach ($file in @('llama.lib', 'ggml.lib', 'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu-x64.dll', 'ggml-cpu-sandybridge.dll', 'ggml-cpu-haswell.dll')) {
    if (-not (Test-Path (Join-Path $Output $file))) { throw "$file がありません" }
}
Write-Host "ビルドしました: $Output"
Get-ChildItem -Path $Output -File | ForEach-Object { Write-Host "  $($_.Name) $($_.Length)" }
