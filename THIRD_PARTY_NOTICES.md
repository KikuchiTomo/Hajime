# Third-Party Notices

s90.tokyo IME includes or is derived from the following software.

## AzooKeyKanaKanjiConverter

https://github.com/azooKey/AzooKeyKanaKanjiConverter (s90.tokyo IME uses a modified fork: https://github.com/KikuchiTomo/AzooKeyKanaKanjiConverter)

```
MIT License

Copyright (c) 2023 Miwa / Ensan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## azooKey-Desktop

https://github.com/azooKey/azooKey-Desktop

```
MIT License

Copyright (c) 2025 Miwa Keita

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## azooKey-Windows

https://github.com/fkunn1326/azooKey-Windows

```
MIT License

Copyright (c) 2026 fkunn1326

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Anthropic Agent Skills

`.claude/skills/skill-creator`, `.claude/skills/frontend-design` and `.claude/skills/webapp-testing` are from https://github.com/anthropics/skills and are licensed under the Apache License 2.0. See `LICENSE.txt` in each directory.

## zenz-v3.2-small (Zenzai model)

Copyright (c) Keita Miwa. https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf (revision c67e03e0)

The model file `ggml-model-Q5_K_M.gguf` is not stored in this repository. It is downloaded by `tools/models/fetch_zenzai.sh`, verified by SHA-256, and bundled into the application unmodified (renamed to `zenz-v3.2-small-Q5_K_M.gguf`). It is licensed under the Apache License 2.0. A copy of the license is in `LICENSES/Apache-2.0.txt`.

This model appears to be based on ku-nlp/gpt2-small-japanese-char (https://huggingface.co/ku-nlp/gpt2-small-japanese-char) by the Kyoto University NLP Lab, which is licensed under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). The model is provided "AS IS", without warranty of any kind.

## azooKey_dictionary_storage

Copyright 2024 Miwa / ensan. https://github.com/azooKey/azooKey_dictionary_storage

The dictionary bundled with AzooKeyKanaKanjiConverter. Licensed under the Apache License 2.0 (`LICENSES/Apache-2.0.txt`).

## llama.cpp

https://github.com/azooKey/llama.cpp (a fork of https://github.com/ggml-org/llama.cpp), used by AzooKeyKanaKanjiConverter to run the Zenzai model.

```
MIT License

Copyright (c) 2023-2024 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## swift-algorithms, swift-collections, swift-numerics

Copyright (c) Apple Inc. and the Swift project authors. https://github.com/apple/swift-algorithms, https://github.com/apple/swift-collections, https://github.com/apple/swift-numerics

Licensed under the Apache License 2.0 with the Runtime Library Exception (`LICENSES/Apache-2.0.txt`).

## swift-tokenizers

https://github.com/ensan-hcl/swift-tokenizers (derived from https://github.com/huggingface/swift-transformers). Licensed under the Apache License 2.0 (`LICENSES/Apache-2.0.txt`).

## Jinja

https://github.com/johnmai-dev/Jinja

```
MIT License

Copyright (c) 2024 John Mai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## SwiftyMarisa

https://github.com/ensan-hcl/SwiftyMarisa. Dual-licensed under the BSD 2-clause license and the LGPL; s90.tokyo IME uses it under the BSD 2-clause license.

```
Copyright (c) 2016, Vladimir Solomenchuk
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 郵便番号データ

日本郵便株式会社「郵便番号データ(住所の郵便番号，UTF-8 版)」<https://www.post.japanpost.jp/service/search/zipcode/download/readme.html> をもとに，`tools/postal/normalize.py` で整えたものを同梱しています．日本郵便株式会社は郵便番号データの著作権を主張していません．
