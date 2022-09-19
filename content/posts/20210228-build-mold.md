---
title: "mold の Build 手順メモ"
date: 2021-02-28T12:00:00+09:00
draft: false
---

## はじめに
[mold と呼ばれる高速なリンカを利用して Chromium を Build してみる](https://south37.hatenablog.com/entry/2021/02/28/mold_%E3%81%A8%E5%91%BC%E3%81%B0%E3%82%8C%E3%82%8B%E9%AB%98%E9%80%9F%E3%81%AA%E3%83%AA%E3%83%B3%E3%82%AB%E3%82%92%E5%88%A9%E7%94%A8%E3%81%97%E3%81%A6_Chromium_%E3%82%92_Build_%E3%81%97%E3%81%A6) という記事の中で、mold と呼ばれる「高速なリンカ」について紹介しました。

https://github.com/rui314/mold

mold は、自分の知る限りでは現時点では特に Binary の配信などは行っていないようです。利用したい場合には repository を git clone して、自分で Build して利用する必要があります。

mold の Build 手順についてメモ程度に記録を残しておこうと思います。

2021年3月20日追記: ちょうど4日ほど前に mold の README に [How to build](https://github.com/rui314/mold#how-to-build) というセクションが追加されたようです。最新のソースコードで Build する場合は、そちらを参照してみてください。cf. https://github.com/rui314/mold#how-to-build

## ステップ1. mold のソースコードを取得する

まず、mold の git repository を clone します。

```
minami@chromium-dev-20210227:~$ git clone https://github.com/rui314/mold.git
minami@chromium-dev-20210227:~$ ls
mold
minami@chromium-dev-20210227:~$ cd mold/
```

mold は自身が依存する mimalloc と oneTBB を `git submodule` として利用しているので、`git submodule update --init` を実行してこれらのソースコードを取得します。

```
minami@chromium-dev-20210227:~/mold$ git submodule update --init
Submodule 'mimalloc' (https://github.com/microsoft/mimalloc.git) registered for path 'mimalloc'
Submodule 'oneTBB' (https://github.com/oneapi-src/oneTBB.git) registered for path 'oneTBB'
Cloning into '/home/minami/mold/mimalloc'...
Cloning into '/home/minami/mold/oneTBB'...
Submodule path 'mimalloc': checked out '4cc8bff90d9e081298ca2c1a94024c7ad4a9e478'
Submodule path 'oneTBB': checked out 'eca91f16d7490a8abfdee652dadf457ec820cc37'
```

これで、必要なソースコードの取得は完了しました。

## ステップ2. 必要な package を install して Build する

`make, libssl-dev, zlib1g-dev, cmake, build-essential` を利用するので、apt で install しておきます（`cmake, build-essential` は git submodule で取り込んだ mimalloc と oneTBB の Build に利用します）。

```
minami@chromium-dev-20210227:~/mold$ sudo apt update
minami@chromium-dev-20210227:~/mold$ sudo apt install -y make libssl-dev zlib1g-dev cmake build-essential
```

`$ make submodules` で、submodule で取り込んだ oneTBB と mimalloc を Build します。

```
minami@chromium-dev-20210227:~/mold$ make submodules
make -C oneTBB
make[1]: Entering directory '/home/minami/mold/oneTBB'
Created the ./build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release directory
make -C "./build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release"  -r -f ../../build/Makefile.tbb cfg=release
make[2]: Entering directory '/home/minami/mold/oneTBB/build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release'
.
.
.
make[2]: Leaving directory '/home/minami/mold/oneTBB/build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release'
make[1]: Leaving directory '/home/minami/mold/oneTBB'
mkdir -p mimalloc/out/release
(cd mimalloc/out/release; cmake ../..)
.
.
.
[100%] Built target mimalloc-test-api
make[2]: Leaving directory '/home/minami/mold/mimalloc/out/release'
make[1]: Leaving directory '/home/minami/mold/mimalloc/out/release'
```

これで、oneTBB と mimalloc の Build は完了しました。

いよいよ、mold の Build を行いたいと思いいます。ただし、この状態では `clang++` が無いのでまだ Build できません。

```
minami@chromium-dev-20210227:~/mold$ make
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o main.o main.cc
make: clang++: Command not found
make: *** [<builtin>: main.o] Error 127
```

`clang++` の install では、https://apt.llvm.org/ の「Automatic installation script」である `bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"` を利用する事にします。

```
minami@chromium-dev-20210227:~/mold$ sudo bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"
--2021-02-27 00:50:07--  https://apt.llvm.org/llvm.sh
.
.
.
Processing triggers for install-info (6.7.0.dfsg.2-5) ...
Processing triggers for libc-bin (2.31-0ubuntu9.2) ...
```

これで、`clang++-11` が install されます（注: 2021/02/27 時点の話で、時期によって最新 version は違うかもしれません）。
`clang++` として利用できるように、symlink を貼っておきます。


```
minami@chromium-dev-20210227:~/mold$ ls /usr/bin | grep clang
clang++-11
clang-11
clang-cpp-11
clangd-11

minami@chromium-dev-20210227:~/mold$ sudo ln -s /usr/bin/clang++-11 /usr/bin/clang++
```

これで clang++ は使えるようになりましたが、まだ「span header が見つからない」というエラーが出る状態です。


```
minami@chromium-dev-20210227:~/mold$ make
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o main.o main.cc
In file included from main.cc:1:
./mold.h:17:10: fatal error: 'span' file not found
#include <span>
         ^~~~~~
1 error generated.
make: *** [<builtin>: main.o] Error 1
```

`make` で実行されているコマンドに `-v` オプションをつけると詳細が表示されるのですが、この include path の中で `span` が見つからないのが原因のようです。

```
minami@chromium-dev-20210227:~/mold$ clang++ -v -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o main.o main.cc
Ubuntu clang version 11.1.0-++20210204121720+1fdec59bffc1-1~exp1~20210203232336.162
Target: x86_64-pc-linux-gnu
Thread model: posix
InstalledDir: /usr/bin
Found candidate GCC installation: /usr/bin/../lib/gcc/x86_64-linux-gnu/9
Found candidate GCC installation: /usr/lib/gcc/x86_64-linux-gnu/9
Selected GCC installation: /usr/bin/../lib/gcc/x86_64-linux-gnu/9
Candidate multilib: .;@m64
Selected multilib: .;@m64
 (in-process)
 "/usr/lib/llvm-11/bin/clang" -cc1 -triple x86_64-pc-linux-gnu -emit-obj -disable-free -disable-llvm-verifier -discard-value-names -main-file-name main.cc -mrelocation-model static -mframe-pointer=none -fmath-errno -fno-rounding-math -mconstructor-aliases -munwind-tables -target-cpu x86-64 -fno-split-dwarf-inlining -debug-info-kind=limited -dwarf-version=4 -debugger-tuning=gdb -v -resource-dir /usr/lib/llvm-11/lib/clang/11.1.0 -I oneTBB/include -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/c++/9 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/x86_64-linux-gnu/c++/9 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/x86_64-linux-gnu/c++/9 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/c++/9/backward -internal-isystem /usr/local/include -internal-isystem /usr/lib/llvm-11/lib/clang/11.1.0/include -internal-externc-isystem /usr/include/x86_64-linux-gnu -internal-externc-isystem /include -internal-externc-isystem /usr/include -O2 -Wno-deprecated-volatile -Wno-switch -std=c++20 -fdeprecated-macro -fdebug-compilation-dir /home/minami/mold -ferror-limit 19 -pthread -fgnuc-version=4.2.1 -fcxx-exceptions -fexceptions -fcolor-diagnostics -vectorize-loops -vectorize-slp -faddrsig -o main.o -x c++ main.cc
clang -cc1 version 11.1.0 based upon LLVM 11.1.0 default target x86_64-pc-linux-gnu
ignoring nonexistent directory "oneTBB/include"
ignoring nonexistent directory "/include"
ignoring duplicate directory "/usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/x86_64-linux-gnu/c++/9"
#include "..." search starts here:
#include <...> search starts here:
 /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/c++/9
 /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/x86_64-linux-gnu/c++/9
 /usr/bin/../lib/gcc/x86_64-linux-gnu/9/../../../../include/c++/9/backward
 /usr/local/include
 /usr/lib/llvm-11/lib/clang/11.1.0/include
 /usr/include/x86_64-linux-gnu
 /usr/include
End of search list.
In file included from main.cc:1:
./mold.h:17:10: fatal error: 'span' file not found
#include <span>
         ^~~~~~
1 error generated.
```

ここで、おもむろに `libstdc++-10-dev` package の install をします。

```
minami@chromium-dev-20210227:~/mold$ sudo apt install -y libstdc++-10-dev
```

上記 package を install すると、ちゃんと `span` header を見つけることができます。

```
minami@chromium-dev-20210227:~/mold$ clang++ -v -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o main.o main.cc
Ubuntu clang version 11.1.0-++20210204121720+1fdec59bffc1-1~exp1~20210203232336.162
Target: x86_64-pc-linux-gnu
Thread model: posix
InstalledDir: /usr/bin
Found candidate GCC installation: /usr/bin/../lib/gcc/x86_64-linux-gnu/10
Found candidate GCC installation: /usr/bin/../lib/gcc/x86_64-linux-gnu/9
Found candidate GCC installation: /usr/lib/gcc/x86_64-linux-gnu/10
Found candidate GCC installation: /usr/lib/gcc/x86_64-linux-gnu/9
Selected GCC installation: /usr/bin/../lib/gcc/x86_64-linux-gnu/10
Candidate multilib: .;@m64
Selected multilib: .;@m64
 (in-process)
 "/usr/lib/llvm-11/bin/clang" -cc1 -triple x86_64-pc-linux-gnu -emit-obj -disable-free -disable-llvm-verifier -discard-value-names -main-file-name main.cc -mrelocation-model static -mframe-pointer=none -fmath-errno -fno-rounding-math -mconstructor-aliases -munwind-tables -target-cpu x86-64 -fno-split-dwarf-inlining -debug-info-kind=limited -dwarf-version=4 -debugger-tuning=gdb -v -resource-dir /usr/lib/llvm-11/lib/clang/11.1.0 -I oneTBB/include -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/x86_64-linux-gnu/c++/10 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/x86_64-linux-gnu/c++/10 -internal-isystem /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10/backward -internal-isystem /usr/local/include -internal-isystem /usr/lib/llvm-11/lib/clang/11.1.0/include -internal-externc-isystem /usr/include/x86_64-linux-gnu -internal-externc-isystem /include -internal-externc-isystem /usr/include -O2 -Wno-deprecated-volatile -Wno-switch -std=c++20 -fdeprecated-macro -fdebug-compilation-dir /home/minami/mold -ferror-limit 19 -pthread -fgnuc-version=4.2.1 -fcxx-exceptions -fexceptions -fcolor-diagnostics -vectorize-loops -vectorize-slp -faddrsig -o main.o -x c++ main.cc
clang -cc1 version 11.1.0 based upon LLVM 11.1.0 default target x86_64-pc-linux-gnu
ignoring nonexistent directory "/include"
ignoring duplicate directory "/usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/x86_64-linux-gnu/c++/10"
#include "..." search starts here:
#include <...> search starts here:
 oneTBB/include
 /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10
 /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/x86_64-linux-gnu/c++/10
 /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10/backward
 /usr/local/include
 /usr/lib/llvm-11/lib/clang/11.1.0/include
 /usr/include/x86_64-linux-gnu
 /usr/include
End of search list.
```

少し探してみると `/usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10` の中に span header があるのを見つけました。これが重要だったようです。

```
minami@chromium-dev-20210227:~/mold$ ls -la /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10/span
-rw-r--r-- 1 root root 13251 Aug  8  2020 /usr/bin/../lib/gcc/x86_64-linux-gnu/10/../../../../include/c++/10/span
```

この状態で make を実行すると、mold の Build が行われて、`mold` Binary が生成されるはずです。

```
minami@chromium-dev-20210227:~/mold$ make
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o output_chunks.o output_chunks.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o mapfile.o mapfile.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o perf.o perf.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o linker_script.o linker_script.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o archive_file.o archive_file.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o output_file.o output_file.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o subprocess.o subprocess.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o gc_sections.o gc_sections.cc
clang++  -g -IoneTBB/include -pthread -std=c++20 -Wno-deprecated-volatile -Wno-switch -O2  -c -o icf.o icf.cc
clang++  main.o object_file.o input_sections.o output_chunks.o mapfile.o perf.o linker_script.o archive_file.o output_file.o subprocess.o gc_sections.o icf.o -o mold -L/home/minami/mold/oneTBB/build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release/ -Wl,-rpath=/home/minami/mold/oneTBB/build/linux_intel64_gcc_cc9.3.0_libc2.31_kernel5.4.0_release/ -L/home/minami/mold/mimalloc/out/release -Wl,-rpath=/home/minami/mold/mimalloc/out/release -lcrypto -pthread -ltbb -lmimalloc
```

以下のように `mold` Binary が生成されていれば成功です 🎉

```
minami@chromium-dev-20210227:~/mold$ ls -la mold
-rwxrwxr-x 1 minami minami 11142376 Feb 27 01:43 mold
```

## まとめ
「高速なリンカである [mold](https://github.com/rui314/mold)」について、Build 手順をまとめました。

今後、mold が広く使われるようになり、package での配信などが行われるようになればここに記載した手順はおそらく不要になると思います。しかしながら、mold はまだ開始したばかりの project であり、開発環境なども未整備の状態です。しばらくは、「自分で Build して動かしてみる」という状態が続くでしょう。

このブログが、「試しに mold を利用してみる」ことへの一助となれば幸いです。
