# protocol

Windows の TSF の DLL と `s90-engine-host` のあいだの通信の定義を置く．Swift と Rust のコードはここから生成し，手で二重に書かない．
形式(Protocol Buffers か，より軽い独自の形式か)は TSF の DLL の大きさを見て ADR で決める．安全の決まりは [docs/dev/SECURITY-MODEL.md](../docs/dev/SECURITY-MODEL.md) の「Windows のプロセス間通信」．
