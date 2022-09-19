---
title: "mold と呼ばれる高速なリンカを利用して Chromium を Build してみる"
date: 2021-02-28T06:00:00+09:00
draft: false
---

## はじめに
現在、広く使われているリンカの中でもっとも高速なものとして有名なのは [LLVM project の LLD](https://lld.llvm.org/) でしょう。LLD のパフォーマンスについては、[公式 document](https://lld.llvm.org/#performance) に以下のような benchmark が掲載されていて、GNU ld, GNU gold などと比較して圧倒的に早いという結果が示されています。

```
Program	        | Output size   | GNU ld	| GNU gold w/o threads  | GNU gold w/threads    | lld w/o threads       | lld w/threads
ffmpeg dbg	| 92 MiB        | 1.72s         | 1.16s	                | 1.01s                 | 0.60s	                | 0.35s
mysqld dbg	| 154 MiB	| 8.50s         | 2.96s	                | 2.68s                 | 1.06s	                | 0.68s
clang dbg	| 1.67 GiB	| 104.03s	| 34.18s	        | 23.49s	        | 14.82s	        | 5.28s
chromium dbg	| 1.14 GiB	| 209.05s [1]	| 64.70s	        | 60.82s	        | 27.60s	        | 16.70s
```

cf. https://lld.llvm.org/#performance

Chromium を [Checking out and building Chromium on Linux](https://chromium.googlesource.com/chromium/src/+/master/docs/linux/build_instructions.md) の手順にしたがって Build する場合、デフォルトで LLD が利用されるようになっています。そのため、何もせずとも「高速なリンク」という恩恵を受けることができるようになっています。

一方、LLD の author である Rui Ueyama さんが最近活発に開発しているのが mold と呼ばれるリンカです。

https://github.com/rui314/mold

こちらは個人 project として開発を進めているようなのですが、既にかなりの完成度のようで、「LLD 以上に高速なリンク」を実現しているようです。

{{<tweet user="rui314" id="1341371659488378881">}}

今日は、この「最も高速なリンカである mold」を利用した Chromium の Build を試してみたいと思います。

## ステップ1. Linux マシンを用意する
この部分は [前回](https://south37.hatenablog.com/entry/2021/02/27/Chromium_%E3%82%92_Build_%E3%81%97%E3%81%A6%E5%8B%95%E3%81%8B%E3%81%99%E3%81%BE%E3%81%A7%E3%81%AE%E5%BE%85%E3%81%A1%E6%99%82%E9%96%93%E3%82%92%E3%80%8C7_%E6%99%82%E9%96%93%E3%80%8D%E3%81%8B%E3%82%89) と同様です。

GCP の Compute Engine で以下の [VM Instance](https://cloud.google.com/compute) を立ててそこで作業を行うことにします。

- 8core, 32GiB memory (E2, e2-standard-8)
- 200GB SSD
- image: Ubuntu 20.04 LTS
- zone: asia-northeast1-b

以下のコマンドで ssh して、そこで作業を行います。

```
$ gcloud beta compute ssh --zone "asia-northeast1-b" <instance 名>
```

## ステップ2. mold を Build する
mold は、自分の知る限りでは現時点では特に Binary の配信などは行っていないようです。利用したい場合には https://github.com/rui314/mold を git clone して、自分で Build して利用する必要があります。

~~この部分の手順は別途またブログにまとめたいと思います。~~ 追記: この部分の手順は [mold の Build 手順メモ](https://south37.hatenablog.com/entry/2021/02/28/mold_%E3%81%AE_Build_%E6%89%8B%E9%A0%86%E3%83%A1%E3%83%A2) に記載しました。そちらを参照してみてください。

`mold` Binary が生成されて、以下のように利用できるようになっていれば OK です。

```console
minami@chromium-dev-20210227:~$ git clone https://github.com/rui314/mold.git

# ここで、mold を Build

minami@chromium-dev-20210227:~$ ls -l /home/minami/mold/mold
-rwxrwxr-x 1 minami minami 11142376 Feb 27 01:43 /home/minami/mold/mold
```

## ステップ3. Chromium の Build 環境を整える。
[Chromium を Build して動かすまでの待ち時間を「7 時間」から「30 分」まで高速化してみる](https://south37.hatenablog.com/entry/2021/02/27/Chromium_%E3%82%92_Build_%E3%81%97%E3%81%A6%E5%8B%95%E3%81%8B%E3%81%99%E3%81%BE%E3%81%A7%E3%81%AE%E5%BE%85%E3%81%A1%E6%99%82%E9%96%93%E3%82%92%E3%80%8C7_%E6%99%82%E9%96%93%E3%80%8D%E3%81%8B%E3%82%89) を参照して、Chromium の Build 環境を整えます。30分 もかからずに、`chrome` Binary を Build できる環境が整うはずです。

## ステップ4. chrome Binary の Build に利用されているリンカを確認しておく

ここでは、事前に「`$ autoninja -C out/Default chrome` で Build をしたときに `chrome` Binary のリンクに利用されていたリンカは何者なのか」をチェックしてみます。

`$ autoninja -C out/Default chrome` を実行して、`[4/4] LINK ./chrome` のタイミングで起動している process を `$ ps fax` で見てみます。そうすると、以下のように `/home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin/ld.lld` が利用されていることが分かります。

```
minami@chromium-dev-20210227:~$ ps fax
    PID TTY      STAT   TIME COMMAND
.
.
.
   1343 pts/0    S+     0:00  |           \_ bash /home/minami/depot_tools/autoninja -C out/Default chrome
   1455 pts/0    S+     0:07  |               \_ /home/minami/depot_tools/ninja-linux64 -C out/Default chrome -j 10
   1484 pts/0    S      0:00  |                   \_ /bin/sh -c python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sor
   1485 pts/0    S      0:00  |                       \_ python ../../build/toolchain/gcc_link_wrapper.py --output=./chrome -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sort -m64 -Wer
   1486 pts/0    S      0:00  |                           \_ ../../third_party/llvm-build/Release+Asserts/bin/clang++ -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sort -m64 -Werror -Wl,--gdb-index -rdynamic -nostdlib++ --sysroot=../../build/li
   1487 pts/0    D      0:03  |                               \_ /home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin/ld.lld @/tmp/response-96ee6b.txt
```

`/home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin` direcotory は以下のように clang や lld が入っていて、「LLVM project の toolchain が格納された directory」のようです。

```
minami@chromium-dev-20210227:~$ cd /home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ ls
clang  clang++  clang-cl  ld64.lld  ld64.lld.darwinnew  ld.lld  lld  lld-link  llvm-ar  llvm-objcopy  llvm-pdbutil  llvm-symbolizer  llvm-undname
```

`ld.lld` は `lld` への `symlink` が貼られています。これが LLVM project の高速なリンカである [LLD](https://lld.llvm.org/) です。

```
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ ls -la ld.lld
lrwxrwxrwx 1 minami minami 3 Dec 12 12:50 ld.lld -> lld
```

```
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ ./ld.lld --help
OVERVIEW: lld

USAGE: ./ld.lld [options] file...
.
.
.
./ld.lld: supported targets: elf
```

LLD が利用されていることは、生成された chrome Binary からも確かめることができます。LLVM project の document である [Using LLD - LLVM](https://lld.llvm.org/#using-lld) には以下のように「`readelf` コマンドで `.comment` section を読み取ると `Linker: LLD` という記述があるはず」と記載されています。

> LLD leaves its name and version number to a .comment section in an output. If you are in doubt whether you are successfully using LLD or not, run `readelf --string-dump .comment <output-file>` and examine the output. If the string “Linker: LLD” is included in the output, you are using LLD.

実際に「Build した `chrome` Binary」に対して `readelf` を実行してみると、確かに  `Linker: LLD 12.0.0` という記述を見つけることができます。

```
minami@chromium-dev-20210227:~/chromium/src$ readelf --string-dump .comment out/Default/chrome

String dump of section '.comment':
  [     0]  GCC: (Debian 7.5.0-3) 7.5.0
  [    1c]  clang version 12.0.0 (https://github.com/llvm/llvm-project/ 6ee22ca6ceb71661e8dbc296b471ace0614c07e5)
  [    82]  Linker: LLD 12.0.0 (https://github.com/llvm/llvm-project/ 6ee22ca6ceb71661e8dbc296b471ace0614c07e5)

```

ここまで、利用されているリンカが何なのかを確認しました。それ以外に、`chrome` Binary の Build の際に実行される script もチェックしておきます。これは、`autoninja` コマンドに `-v` オプションをつけることで出力することができます。この情報は後々利用します。

```
minami@chromium-dev-20210227:~/chromium/src$ time autoninja -v -C out/Default chrome
ninja: Entering directory `out/Default'
[1/4] ../../third_party/llvm-build/Release+Asserts/bin/clang++ -MMD -MF obj/chrome/common/channel_info/channel_info.o.d -DUSE_UDEV -DUSE_AURA=1 -DUSE_GLIB=1 -DUSE_NSS_CERTS=1 -DUSE_OZONE=1 -DUSE_X11=1 -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_GNU_SOURCE -DCR_CLANG_REVISION=\"llvmorg-12-init-12923-g6ee22ca6-1\" -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -DCOMPONENT_BUILD -D_LIBCPP_ABI_UNSTABLE -D_LIBCPP_ABI_VERSION=Cr -D_LIBCPP_ENABLE_NODISCARD -D_LIBCPP_DEBUG=0 -DCR_LIBCXX_REVISION=375504 -DCR_SYSROOT_HASH=22f2db7711f7426a364617bb6d78686cce09a8f9 -D_DEBUG -DDYNAMIC_ANNOTATIONS_ENABLED=1 -DGLIB_VERSION_MAX_ALLOWED=GLIB_VERSION_2_40 -DGLIB_VERSION_MIN_REQUIRED=GLIB_VERSION_2_40 -DWEBP_EXTERN=extern -DABSL_CONSUME_DLL -DBORINGSSL_SHARED_LIBRARY -I../.. -Igen -I../../third_party/perfetto/include -Igen/third_party/perfetto/build_config -Igen/third_party/perfetto -I../../third_party/libwebp/src -I../../third_party/abseil-cpp -I../../third_party/boringssl/src/include -I../../third_party/protobuf/src -Igen/protoc_out -fno-delete-null-pointer-checks -fno-strict-aliasing --param=ssp-buffer-size=4 -fstack-protector -funwind-tables -fPIC -pthread -fcolor-diagnostics -fmerge-all-constants -fcrash-diagnostics-dir=../../tools/clang/crashreports -mllvm -instcombine-lower-dbg-declare=0 -fcomplete-member-pointers -m64 -march=x86-64 -msse3 -Wno-builtin-macro-redefined -D__DATE__= -D__TIME__= -D__TIMESTAMP__= -Xclang -fdebug-compilation-dir -Xclang . -no-canonical-prefixes -Wall -Werror -Wextra -Wimplicit-fallthrough -Wunreachable-code -Wthread-safety -Wextra-semi -Wno-missing-field-initializers -Wno-unused-parameter -Wno-c++11-narrowing -Wno-unneeded-internal-declaration -Wno-undefined-var-template -Wno-psabi -Wno-ignored-pragma-optimize -Wno-implicit-int-float-conversion -Wno-final-dtor-non-final-class -Wno-builtin-assume-aligned-alignment -Wno-deprecated-copy -Wno-non-c-typedef-for-linkage -Wmax-tokens -O0 -fno-omit-frame-pointer -g2 -Xclang -debug-info-kind=constructor -gsplit-dwarf -ggnu-pubnames -ftrivial-auto-var-init=pattern -fvisibility=hidden -Xclang -add-plugin -Xclang find-bad-constructs -Xclang -plugin-arg-find-bad-constructs -Xclang check-ipc -Wheader-hygiene -Wstring-conversion -Wtautological-overlap-compare -isystem../../build/linux/debian_sid_amd64-sysroot/usr/include/glib-2.0 -isystem../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu/glib-2.0/include -DPROTOBUF_ALLOW_DEPRECATED=1 -Wno-undefined-bool-conversion -Wno-tautological-undefined-compare -std=c++14 -fno-trigraphs -Wno-trigraphs -fno-exceptions -fno-rtti -nostdinc++ -isystem../../buildtools/third_party/libc++/trunk/include -isystem../../buildtools/third_party/libc++abi/trunk/include --sysroot=../../build/linux/debian_sid_amd64-sysroot -fvisibility-inlines-hidden -c ../../chrome/common/channel_info.cc -o obj/chrome/common/channel_info/channel_info.o
[2/4] touch obj/chrome/common/channel_info.stamp
[3/4] python "../../build/toolchain/gcc_solink_wrapper.py" --readelf="readelf" --nm="nm"  --sofile="./libvr_common.so" --tocfile="./libvr_common.so.TOC" --output="./libvr_common.so" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -shared -Wl,-soname="libvr_common.so" -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sort -m64 -Werror -Wl,--gdb-index -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -Wl,-rpath=\$ORIGIN -o "./libvr_common.so" @"./libvr_common.so.rsp"
[4/4] python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sort -m64 -Werror -Wl,--gdb-index -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -pie -Wl,--disable-new-dtags -Wl,-rpath=\$ORIGIN -o "./chrome" -Wl,--start-group @"./chrome.rsp" ./libbase.so ./libabsl.so ./libboringssl.so ./libperfetto.so ./libbindings.so ./libbindings_base.so ./libmojo_public_system_cpp.so ./libmojo_public_system.so ./libmojo_cpp_platform.so ./libmessage_support.so ./libmojo_mojom_bindings.so ./libmojo_mojom_bindings_shared.so ./liburl_mojom_traits.so ./libmojo_base_mojom_shared.so ./libmojo_base_shared_typemap_traits.so ./libmojo_base_lib.so ./libbase_i18n.so ./libicui18n.so ./libicuuc.so ./liburl.so ./libui_base.so ./libui_base_features.so ./libui_data_pack.so ./libskia.so ./libgfx.so ./libcolor_space.so ./libcolor_utils.so ./libgeometry.so ./libgeometry_skia.so ./libgfx_switches.so ./libanimation.so ./libcodec.so ./librange.so ./libcc_paint.so ./libcc_base.so ./libcc_debug.so ./libfile_info.so ./libevents_base.so ./libplatform.so ./libkeycodes_x11.so ./libui_base_x.so ./libcontent_public_common_mojo_bindings_shared.so ./libmojom_platform_shared.so ./libandroid_mojo_bindings_shared.so ./libauthenticator_test_mojo_bindings_shared.so ./libcolor_scheme_mojo_bindings_shared.so ./libmojom_mhtml_load_result_shared.so ./libscript_type_mojom_shared.so ./libweb_feature_mojo_bindings_mojom_shared.so ./libservice_manager_mojom_shared.so ./libservice_manager_mojom_constants_shared.so ./libdom_storage_mojom_shared.so ./libframe_mojom_shared.so ./libblink_gpu_mojom_shared.so ./libservice_worker_storage_mojom_shared.so ./libtokens_mojom_shared.so ./libusb_shared.so ./libmojo_base_mojom.so ./libmojo_base_typemap_traits.so ./libcontent_settings_features.so ./libipc.so ./libipc_mojom.so ./libipc_mojom_shared.so ./libprotobuf_lite.so ./libtracing_cpp.so ./libstartup_tracing.so ./libtracing_mojom.so ./libtracing_mojom_shared.so ./libnet.so ./libcrcrypto.so ./libskia_shared_typemap_traits.so ./libcontent.so ./libgpu.so ./libmailbox.so ./libcrash_key_lib.so ./libchrome_zlib.so ./libvulkan_info.so ./libgfx_ipc.so ./libgfx_ipc_geometry.so ./libvulkan_ycbcr_info.so ./liburl_ipc.so ./libviz_common.so ./libviz_resource_format_utils.so ./libviz_vulkan_context_provider.so ./libdisplay.so ./libdisplay_types.so ./libgl_wrapper.so ./libmedia.so ./libshared_memory_support.so ./libleveldb_proto.so ./libkeyed_service_core.so ./libleveldatabase.so ./libgfx_ipc_color.so ./libgfx_ipc_buffer_types.so ./libgfx_ipc_skia.so ./libgfx_native_types_shared_mojom_traits.so ./libgfx_shared_mojom_traits.so ./libgpu_shared_mojom_traits.so ./liblearning_common.so ./libmedia_learning_shared_typemap_traits.so ./libmedia_session_base_cpp.so ./libcookies_mojom_support.so ./libnetwork_cpp_base.so ./libcrash_keys.so ./libcross_origin_embedder_policy.so ./libip_address_mojom_support.so ./libschemeful_site_mojom_support.so ./libwebrtc_component.so ./libservice_manager_mojom.so ./libservice_manager_mojom_constants.so ./libservice_manager_cpp_types.so ./libservice_manager_mojom_traits.so ./libservice_manager_cpp.so ./libmetrics_cpp.so ./libui_base_clipboard_types.so ./libevents.so ./libui_base_cursor_base.so ./libdisplay_shared_mojom_traits.so ./libcc.so ./libvideo_capture_mojom_support.so ./libcapture_base.so ./liblatency_shared_mojom_traits.so ./libprediction.so ./libblink_common.so ./libprivacy_budget.so ./libnetwork_cpp.so ./libweb_feature_mojo_bindings_mojom.so ./libmojom_modules_shared.so ./libmojom_core_shared.so ./libfido.so ./libbluetooth.so ./libscript_type_mojom.so ./libcc_ipc.so ./libcc_shared_mojom_traits.so ./libdom_storage_mojom.so ./libframe_mojom.so ./libblink_gpu_mojom.so ./libservice_worker_storage_mojom.so ./libtokens_traits.so ./libime_shared_mojom_traits.so ./libui_base_ime_types.so ./libui_events_ipc.so ./libweb_bluetooth_mojo_bindings_shared.so ./libax_base.so ./libui_accessibility_ax_mojom.so ./libui_accessibility_ax_mojom_shared.so ./libui_base_ime.so ./libcontent_common_mojo_bindings_shared.so ./libaccessibility.so ./libgfx_x11.so ./libxprotos.so ./libaura.so ./libcompositor.so ./libblink_features.so ./libsurface.so ./libpolicy.so ./libnetwork_service.so ./libmemory_instrumentation.so ./libresource_coordinator_public_mojom.so ./libresource_coordinator_public_mojom_shared.so ./libstorage_common.so ./libpublic.so ./libinterfaces_shared.so ./libstorage_service_filesystem_mojom_shared.so ./libstorage_service_filesystem_mojom.so ./libstorage_service_typemap_traits.so ./libmedia_session_cpp.so ./libstorage_browser.so ./libvr_public_cpp.so ./libdevice_vr_isolated_xr_service_mojo_bindings.so ./libdevice_vr_isolated_xr_service_mojo_bindings_shared.so ./libdevice_vr_test_mojo_bindings_shared.so ./libdevice_vr_service_mojo_bindings_shared.so ./libgamepad_mojom_shared.so ./libdevice_vr_test_mojo_bindings.so ./libdevice_vr_service_mojo_bindings.so ./libgamepad_mojom.so ./libgamepad_shared_typemap_traits.so ./libshared_with_blink.so ./libdevice_vr_public_typemaps.so ./libchrome_features.so ./libprefs.so ./libvariations_features.so ./liburl_matcher.so ./libcapture_lib.so ./libmedia_webrtc.so ./libwtf.so ./libcommon.so ./libnetwork_session_configurator.so ./libsql.so ./libchromium_sqlite3.so ./libwebdata_common.so ./libos_crypt.so ./libomnibox_http_headers.so ./libcloud_policy_proto_generated_compile.so ./libpolicy_component.so ./libpolicy_proto.so ./libgcm.so ./libnative_theme.so ./libservice_provider.so ./libui_message_center_cpp.so ./libppapi_shared.so ./libmojo_core_embedder.so ./libprinting.so ./libsandbox_services.so ./libsuid_sandbox_client.so ./libseccomp_bpf.so ./libsecurity_state_features.so ./libui_base_clipboard.so ./libui_base_data_transfer_policy.so ./libkeyed_service_content.so ./libuser_prefs.so ./libextras.so ./libsessions.so ./libcaptive_portal_core.so ./libdevice_features.so ./libweb_modal.so ./libdevice_event_log.so ./libshell_dialogs.so ./libui_base_idle.so ./libdbus.so ./libonc.so ./libhost.so ./libukm_recorder.so ./libcrdtp.so ./libuser_manager.so ./libperformance_manager_public_mojom.so ./libperformance_manager_public_mojom_shared.so ./libviews.so ./libui_base_ime_init.so ./libui_base_cursor_theme_manager.so ./libui_base_cursor.so ./libx11_window.so ./libui_touch_selection.so ./libproxy_config.so ./libtab_groups.so ./libmanager.so ./libmessage_center.so ./libfontconfig.so ./libx11_events_platform.so ./libdevices.so ./libevents_devices_x11.so ./libevents_x.so ./libffmpeg.so ./libwebview.so ./libdomain_reliability.so ./liblookalikes_features.so ./libui_devtools.so ./libdata_exchange.so ./libgesture_detection.so ./libsnapshot.so ./libweb_dialogs.so ./libcolor.so ./libmixers.so ./libdiscardable_memory_service.so ./libAPP_UPDATE.so ./libozone.so ./libozone_base.so ./libdisplay_util.so ./libvulkan_wrapper.so ./libplatform_window.so ./libui_base_ime_linux.so ./libfreetype_harfbuzz.so ./libmenu.so ./libproperties.so ./libthread_linux.so ./libgtk.so ./libgtk_ui_delegate.so ./libbrowser_ui_views.so ./libwm.so ./libmedia_message_center.so ./libtab_count_metrics.so ./libui_gtk_x.so ./libwm_public.so ./libppapi_host.so ./libppapi_proxy.so ./libcertificate_matching.so ./libdevice_base.so ./libswitches.so ./libcapture_switches.so ./libmidi.so ./libmedia_mojo_services.so ./libmedia_gpu.so ./libgles2_utils.so ./libgles2.so ./libgpu_ipc_service.so ./libgl_init.so ./libcert_net_url_loader.so ./liberror_reporting.so ./libevents_ozone.so ./libschema_org_common.so ./libmirroring_service.so ./libvr_common.so ./libvr_base.so ./libdevice_vr.so ./libblink_controller.so ./libblink_core.so ./libblink_mojom_broadcastchannel_bindings_shared.so ./libwtf_support.so ./libweb_feature_mojo_bindings_mojom_blink.so ./libmojo_base_mojom_blink.so ./libservice_manager_mojom_blink.so ./libservice_manager_mojom_constants_blink.so ./libblink_platform.so ./libcc_animation.so ./libresource_coordinator_public_mojom_blink.so ./libv8.so ./libblink_embedded_frame_sink_mojo_bindings_shared.so ./libperformance_manager_public_mojom_blink.so ./libui_accessibility_ax_mojom_blink.so ./libgin.so ./libblink_modules.so ./libgamepad_mojom_blink.so ./liburlpattern.so ./libdevice_vr_service_mojo_bindings_blink.so ./libdevice_vr_test_mojo_bindings_blink.so ./libdiscardable_memory_client.so ./libcbor.so ./libpdfium.so ./libheadless_non_renderer.so ./libc++.so -Wl,--end-group  -ldl -lpthread -lrt -lgmodule-2.0 -lgobject-2.0 -lgthread-2.0 -lglib-2.0 -lnss3 -lnssutil3 -lsmime3 -lplds4 -lplc4 -lnspr4 -latk-1.0 -latk-bridge-2.0 -lcups -ldbus-1 -lgio-2.0 -lexpat

real    0m15.202s
user    0m19.157s
sys     0m4.398s
```

## ステップ5. mold を利用して `chrome` Binary をリンクしてみる

さて、ここまでで「`chrome` のリンクに LLD が利用されていること」、「コマンドとしては `/home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin/ld.lld` が利用されていること」が確認できました。

次は、LLD の代わりに mold を利用してみたいと思います。ここでは、「`ld.lld` の symlink の向き先を `lld` から `mold` に切り替えて、Build する」というアプローチをとってみます。
以下のように `ld.lld` を消して、symlink の向き先を `/home/minami/mold/mold` に変えてみます。

```
minami@chromium-dev-20210227:~$ cd /home/minami/chromium/src/out/Default/../../third_party/llvm-build/Release+Asserts/bin
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ rm ld.lld
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ ln -s /home/minami/mold/mold ld.lld
minami@chromium-dev-20210227:~/chromium/src/third_party/llvm-build/Release+Asserts/bin$ ls -la ld.lld
lrwxrwxrwx 1 minami minami 22 Feb 28 03:06 ld.lld -> /home/minami/mold/mold
```

これで、mold が利用されるようになるはずです。この状態で再度 chrome の Build をしてみます。

ただ、この状態で `$ autoninja -C out/Default chrome` を実行すると、以下のように `[3/4] SOLINK ./libvr_common.so` のステップでリンクに失敗してしまします。

```
minami@chromium-dev-20210227:~/chromium/src$ time autoninja -C out/Default chrome
ninja: Entering directory `out/Default'
[3/4] SOLINK ./libvr_common.so
FAILED: libvr_common.so libvr_common.so.TOC
python "../../build/toolchain/gcc_solink_wrapper.py" --readelf="readelf" --nm="nm"  --sofile="./libvr_common.so" --tocfile="./libvr_common.so.TOC" --output="./libvr_common.so" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -shared -Wl,-soname="libvr_common.so" -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -Wl,--color-diagnostics -Wl,--no-call-graph-profile-sort -m64 -Werror -Wl,--gdb-index -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -Wl,-rpath=\$ORIGIN -o "./libvr_common.so" @"./libvr_common.so.rsp"
mold: unknown command line option: -soname=libvr_common.so
clang: error: linker command failed with exit code 1 (use -v to see invocation)
ninja: build stopped: subcommand failed.

real    0m5.480s
user    0m4.577s
sys     0m0.746s
```

mold が `-soname` オプションをサポートしてないために、エラーが出ているようです。

上記の `python "../../build/toolchain/gcc_solink_wrapper.py" ...` という部分が `[3/4] SOLINK ./libvr_common.so` のステップとして実際に実行されているコマンドです。ここから、「mold がサポートしていないオプション」を消して、同じコマンドを手動で実行してみます。具体的には、`-soname` , `--color-diagnostics`, `--no-call-graph-profile-sort`, `--gdb-index` オプションの指定を消して、以下のように実行します。こうすると、ちゃんと mold によるリンクに成功して、 `libvr_common.so` という Shared Object File が生成されます。

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_solink_wrapper.py" --readelf="readelf" --nm="nm"  --sofile="./libvr_common.so" --tocfile="./libvr_common.so.TOC" --output="./libvr_common.so" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -shared -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -m64 -Werror -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -Wl,-rpath=\$ORIGIN -o "./libvr_common.so" @"./libvr_common.so.rsp"

real    0m0.563s
user    0m0.033s
sys     0m0.029s

minami@chromium-dev-20210227:~/chromium/src/out/Default$ ls -la libvr_common.so
-rwxrwxr-x 1 minami minami 192508187 Feb 28 03:14 libvr_common.so
```

上記の python script の実行が、`[3/4] SOLINK ./libvr_common.so` に相当する処理でした。さらに、 `[4/4] LINK ./chrome` に相当する処理も、直接 python script の実行を行う事にします。これは、ステップ4の最後に `$ autoninja -v -C out/Default chrome` コマンドで出力したコマンドの、`[4/4] python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ...(長いので省略)` が該当します。

ただ、この状態で `[4/4] LINK ./chrome`に相当する python script を実行しても、以下のように `chrome.rsp` という File が無いことで失敗してしまいます。

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ...(長いので省略)
clang: error: no such file or directory: '@./chrome.rsp'
```

そこで、一度 `ld.lld` の symlink 先を lld に戻してから、`$ autoninja -C out/Default chrome` の実行中に `[4/4] LINK ./chrome` のタイミングで Ctrl-C で python script を強制 exit してみます。
こうすることで、「`libvr_common.so` と`chrome.rsp` が存在する状態（ちょうど  `[4/4] LINK ./chrome` の開始前の状態」を再現することが出来ます。

```
minami@chromium-dev-20210227:~/chromium/src$ ls out/Default/libvr_common.so
out/Default/libvr_common.so
minami@chromium-dev-20210227:~/chromium/src$ ls out/Default/chrome.rsp
out/Default/chrome.rsp
```

この状態で、再度 `ld.lld` の symlink 先を mold にしてから、`[4/4] LINK ./chrome` に相当する python script を手動で実行します。mold でサポートされてない `--color-diagnostics`, `--no-call-graph-profile-sort`, `--gdb-index`オプションの指定は消しておきます。
こうすると、以下のようにちゃんとリンクに成功します。`chrome` Binary が生成されたことも確認できます。

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -m64 -Werror -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -pie -Wl,--disable-new-dtags -Wl,-rpath=\$ORIGIN -o "./chrome" -Wl,--start-group @"./chrome.rsp" ./libbase.so ./libabsl.so ./libboringssl.so ./libperfetto.so ./libbindings.so ./libbindings_base.so ./libmojo_public_system_cpp.so ./libmojo_public_system.so ./libmojo_cpp_platform.so ./libmessage_support.so ./libmojo_mojom_bindings.so ./libmojo_mojom_bindings_shared.so ./liburl_mojom_traits.so ./libmojo_base_mojom_shared.so ./libmojo_base_shared_typemap_traits.so ./libmojo_base_lib.so ./libbase_i18n.so ./libicui18n.so ./libicuuc.so ./liburl.so ./libui_base.so ./libui_base_features.so ./libui_data_pack.so ./libskia.so ./libgfx.so ./libcolor_space.so ./libcolor_utils.so ./libgeometry.so ./libgeometry_skia.so ./libgfx_switches.so ./libanimation.so ./libcodec.so ./librange.so ./libcc_paint.so ./libcc_base.so ./libcc_debug.so ./libfile_info.so ./libevents_base.so ./libplatform.so ./libkeycodes_x11.so ./libui_base_x.so ./libcontent_public_common_mojo_bindings_shared.so ./libmojom_platform_shared.so ./libandroid_mojo_bindings_shared.so ./libauthenticator_test_mojo_bindings_shared.so ./libcolor_scheme_mojo_bindings_shared.so ./libmojom_mhtml_load_result_shared.so ./libscript_type_mojom_shared.so ./libweb_feature_mojo_bindings_mojom_shared.so ./libservice_manager_mojom_shared.so ./libservice_manager_mojom_constants_shared.so ./libdom_storage_mojom_shared.so ./libframe_mojom_shared.so ./libblink_gpu_mojom_shared.so ./libservice_worker_storage_mojom_shared.so ./libtokens_mojom_shared.so ./libusb_shared.so ./libmojo_base_mojom.so ./libmojo_base_typemap_traits.so ./libcontent_settings_features.so ./libipc.so ./libipc_mojom.so ./libipc_mojom_shared.so ./libprotobuf_lite.so ./libtracing_cpp.so ./libstartup_tracing.so ./libtracing_mojom.so ./libtracing_mojom_shared.so ./libnet.so ./libcrcrypto.so ./libskia_shared_typemap_traits.so ./libcontent.so ./libgpu.so ./libmailbox.so ./libcrash_key_lib.so ./libchrome_zlib.so ./libvulkan_info.so ./libgfx_ipc.so ./libgfx_ipc_geometry.so ./libvulkan_ycbcr_info.so ./liburl_ipc.so ./libviz_common.so ./libviz_resource_format_utils.so ./libviz_vulkan_context_provider.so ./libdisplay.so ./libdisplay_types.so ./libgl_wrapper.so ./libmedia.so ./libshared_memory_support.so ./libleveldb_proto.so ./libkeyed_service_core.so ./libleveldatabase.so ./libgfx_ipc_color.so ./libgfx_ipc_buffer_types.so ./libgfx_ipc_skia.so ./libgfx_native_types_shared_mojom_traits.so ./libgfx_shared_mojom_traits.so ./libgpu_shared_mojom_traits.so ./liblearning_common.so ./libmedia_learning_shared_typemap_traits.so ./libmedia_session_base_cpp.so ./libcookies_mojom_support.so ./libnetwork_cpp_base.so ./libcrash_keys.so ./libcross_origin_embedder_policy.so ./libip_address_mojom_support.so ./libschemeful_site_mojom_support.so ./libwebrtc_component.so ./libservice_manager_mojom.so ./libservice_manager_mojom_constants.so ./libservice_manager_cpp_types.so ./libservice_manager_mojom_traits.so ./libservice_manager_cpp.so ./libmetrics_cpp.so ./libui_base_clipboard_types.so ./libevents.so ./libui_base_cursor_base.so ./libdisplay_shared_mojom_traits.so ./libcc.so ./libvideo_capture_mojom_support.so ./libcapture_base.so ./liblatency_shared_mojom_traits.so ./libprediction.so ./libblink_common.so ./libprivacy_budget.so ./libnetwork_cpp.so ./libweb_feature_mojo_bindings_mojom.so ./libmojom_modules_shared.so ./libmojom_core_shared.so ./libfido.so ./libbluetooth.so ./libscript_type_mojom.so ./libcc_ipc.so ./libcc_shared_mojom_traits.so ./libdom_storage_mojom.so ./libframe_mojom.so ./libblink_gpu_mojom.so ./libservice_worker_storage_mojom.so ./libtokens_traits.so ./libime_shared_mojom_traits.so ./libui_base_ime_types.so ./libui_events_ipc.so ./libweb_bluetooth_mojo_bindings_shared.so ./libax_base.so ./libui_accessibility_ax_mojom.so ./libui_accessibility_ax_mojom_shared.so ./libui_base_ime.so ./libcontent_common_mojo_bindings_shared.so ./libaccessibility.so ./libgfx_x11.so ./libxprotos.so ./libaura.so ./libcompositor.so ./libblink_features.so ./libsurface.so ./libpolicy.so ./libnetwork_service.so ./libmemory_instrumentation.so ./libresource_coordinator_public_mojom.so ./libresource_coordinator_public_mojom_shared.so ./libstorage_common.so ./libpublic.so ./libinterfaces_shared.so ./libstorage_service_filesystem_mojom_shared.so ./libstorage_service_filesystem_mojom.so ./libstorage_service_typemap_traits.so ./libmedia_session_cpp.so ./libstorage_browser.so ./libvr_public_cpp.so ./libdevice_vr_isolated_xr_service_mojo_bindings.so ./libdevice_vr_isolated_xr_service_mojo_bindings_shared.so ./libdevice_vr_test_mojo_bindings_shared.so ./libdevice_vr_service_mojo_bindings_shared.so ./libgamepad_mojom_shared.so ./libdevice_vr_test_mojo_bindings.so ./libdevice_vr_service_mojo_bindings.so ./libgamepad_mojom.so ./libgamepad_shared_typemap_traits.so ./libshared_with_blink.so ./libdevice_vr_public_typemaps.so ./libchrome_features.so ./libprefs.so ./libvariations_features.so ./liburl_matcher.so ./libcapture_lib.so ./libmedia_webrtc.so ./libwtf.so ./libcommon.so ./libnetwork_session_configurator.so ./libsql.so ./libchromium_sqlite3.so ./libwebdata_common.so ./libos_crypt.so ./libomnibox_http_headers.so ./libcloud_policy_proto_generated_compile.so ./libpolicy_component.so ./libpolicy_proto.so ./libgcm.so ./libnative_theme.so ./libservice_provider.so ./libui_message_center_cpp.so ./libppapi_shared.so ./libmojo_core_embedder.so ./libprinting.so ./libsandbox_services.so ./libsuid_sandbox_client.so ./libseccomp_bpf.so ./libsecurity_state_features.so ./libui_base_clipboard.so ./libui_base_data_transfer_policy.so ./libkeyed_service_content.so ./libuser_prefs.so ./libextras.so ./libsessions.so ./libcaptive_portal_core.so ./libdevice_features.so ./libweb_modal.so ./libdevice_event_log.so ./libshell_dialogs.so ./libui_base_idle.so ./libdbus.so ./libonc.so ./libhost.so ./libukm_recorder.so ./libcrdtp.so ./libuser_manager.so ./libperformance_manager_public_mojom.so ./libperformance_manager_public_mojom_shared.so ./libviews.so ./libui_base_ime_init.so ./libui_base_cursor_theme_manager.so ./libui_base_cursor.so ./libx11_window.so ./libui_touch_selection.so ./libproxy_config.so ./libtab_groups.so ./libmanager.so ./libmessage_center.so ./libfontconfig.so ./libx11_events_platform.so ./libdevices.so ./libevents_devices_x11.so ./libevents_x.so ./libffmpeg.so ./libwebview.so ./libdomain_reliability.so ./liblookalikes_features.so ./libui_devtools.so ./libdata_exchange.so ./libgesture_detection.so ./libsnapshot.so ./libweb_dialogs.so ./libcolor.so ./libmixers.so ./libdiscardable_memory_service.so ./libAPP_UPDATE.so ./libozone.so ./libozone_base.so ./libdisplay_util.so ./libvulkan_wrapper.so ./libplatform_window.so ./libui_base_ime_linux.so ./libfreetype_harfbuzz.so ./libmenu.so ./libproperties.so ./libthread_linux.so ./libgtk.so ./libgtk_ui_delegate.so ./libbrowser_ui_views.so ./libwm.so ./libmedia_message_center.so ./libtab_count_metrics.so ./libui_gtk_x.so ./libwm_public.so ./libppapi_host.so ./libppapi_proxy.so ./libcertificate_matching.so ./libdevice_base.so ./libswitches.so ./libcapture_switches.so ./libmidi.so ./libmedia_mojo_services.so ./libmedia_gpu.so ./libgles2_utils.so ./libgles2.so ./libgpu_ipc_service.so ./libgl_init.so ./libcert_net_url_loader.so ./liberror_reporting.so ./libevents_ozone.so ./libschema_org_common.so ./libmirroring_service.so ./libvr_common.so ./libvr_base.so ./libdevice_vr.so ./libblink_controller.so ./libblink_core.so ./libblink_mojom_broadcastchannel_bindings_shared.so ./libwtf_support.so ./libweb_feature_mojo_bindings_mojom_blink.so ./libmojo_base_mojom_blink.so ./libservice_manager_mojom_blink.so ./libservice_manager_mojom_constants_blink.so ./libblink_platform.so ./libcc_animation.so ./libresource_coordinator_public_mojom_blink.so ./libv8.so ./libblink_embedded_frame_sink_mojo_bindings_shared.so ./libperformance_manager_public_mojom_blink.so ./libui_accessibility_ax_mojom_blink.so ./libgin.so ./libblink_modules.so ./libgamepad_mojom_blink.so ./liburlpattern.so ./libdevice_vr_service_mojo_bindings_blink.so ./libdevice_vr_test_mojo_bindings_blink.so ./libdiscardable_memory_client.so ./libcbor.so ./libpdfium.so ./libheadless_non_renderer.so ./libc++.so -Wl,--end-group  -ldl -lpthread -lrt -lgmodule-2.0 -lgobject-2.0 -lgthread-2.0 -lglib-2.0 -lnss3 -lnssutil3 -lsmime3 -lplds4 -lplc4 -lnspr4 -latk-1.0 -latk-bridge-2.0 -lcups -ldbus-1 -lgio-2.0 -lexpat

real    0m3.312s
user    0m0.064s
sys     0m0.027s

minami@chromium-dev-20210227:~/chromium/src/out/Default$ ls -la chrome
-rwxrwxr-x 1 minami minami 1296141738 Feb 28 03:46 chrome
```

この `chrome` の `.comment` section を見て、出自を確認してみましょう。LLD でリンクした時は `Linker: LLD 12.0.0` という記述があったのに対して、この chrome Binary にはその記述がありません。逆説的に、「LLD 以外のリンカ（= mold）でリンクしたこと」が確認できたと言えそうです。

```
minami@chromium-dev-20210227:~/chromium/src$ readelf --string-dump .comment out/Default/chrome

String dump of section '.comment':
  [     1]  GCC: (Debian 7.5.0-3) 7.5.0
  [    1d]  clang version 12.0.0 (https://github.com/llvm/llvm-project/ 6ee22ca6ceb71661e8dbc296b471ace0614c07e5)

```

2021年3月27日追記: mold の README の [How to use](https://github.com/rui314/mold#how-to-use) を見ると、今では `.comment` section に `mold` という文字列が commit hash つきで記載されるようになったようです（ただし、自分は動作未検証です）。

生成した chrome Binary の挙動も確認してみましょう。[以前のブログ記事](https://south37.hatenablog.com/entry/2021/01/25/Chromium_%E3%82%92%E3%82%BC%E3%83%AD%E3%81%8B%E3%82%89_Build_%E3%81%97%E3%81%A6%E5%8B%95%E3%81%8B%E3%81%97%E3%81%A6%E3%81%BF%E3%82%8B) のように、「headless mode での実行」を試してみます。以下のようにちゃんと動作をすることが確認できました 🎉

```
minami@chromium-dev-20210227:~/chromium/src$ ./out/Default/chrome --headless --disable-gpu --dump-dom https://example.com
[0228/035317.179292:WARNING:headless_content_main_delegate.cc(530)] Cannot create Pref Service with no user data dir.
[0228/035317.194952:INFO:content_main_runner_impl.cc(1027)] Chrome is running in full browser mode.
<!DOCTYPE html>
.
.
.
```

ということで、無事「mold による chrome Binary のリンク」に成功しました。

既存の Build の仕組みに組み込もうと思うと「mold ではサポートされてない option の扱い」などいくつか考える必要がありそうですが、試しにリンクをするだけであれば比較的簡単に実行ができることが分かりました。

## LLD と mold の速度比較

mold は「LLD よりも高速なリンカ」として開発されています。実際に、リンクにかかる時間がどれだけ変わったのか、比較してみましょう。ここでは、上記の「リンカに渡す option を減らした状態でのリンクの実行」を mold と LLD の両方で行って、time で計測した結果を載せています。

### LLD

- `[3/4] SOLINK ./libvr_common.so` 相当の処理

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_solink_wrapper.py" --readelf="readelf" --nm="nm"  --sofile="./libvr_common.so" --tocfile="./libvr_common.so.TOC" --output="./libvr_common.so" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -shared -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -m64 -Werror -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -Wl,-rpath=\$ORIGIN -o "./libvr_common.so" @"./libvr_common.so.rsp"

real    0m1.265s
user    0m1.391s
sys     0m0.837s
```

- `[4/4] LINK ./chrome` 相当の処理

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ...(長いので省略)

real    0m7.777s
user    0m8.309s
sys     0m3.664s
```

### mold

- `[3/4] SOLINK ./libvr_common.so` 相当の処理

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_solink_wrapper.py" --readelf="readelf" --nm="nm"  --sofile="./libvr_common.so" --tocfile="./libvr_common.so.TOC" --output="./libvr_common.so" -- ../../third_party/llvm-build/Release+Asserts/bin/clang++ -shared -fuse-ld=lld -Wl,--fatal-warnings -Wl,--build-id -fPIC -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,defs -Wl,--as-needed -m64 -Werror -rdynamic -nostdlib++ --sysroot=../../build/linux/debian_sid_amd64-sysroot -L../../build/linux/debian_sid_amd64-sysroot/usr/local/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/lib/x86_64-linux-gnu -L../../build/linux/debian_sid_amd64-sysroot/usr/lib/x86_64-linux-gnu -Wl,-rpath=\$ORIGIN -o "./libvr_common.so" @"./libvr_common.so.rsp"

real    0m0.563s
user    0m0.033s
sys     0m0.029s
```

-  `[4/4] LINK ./chrome` 相当の処理

```
minami@chromium-dev-20210227:~/chromium/src/out/Default$ time python "../../build/toolchain/gcc_link_wrapper.py" --output="./chrome" -- ...(長いので省略)

real    0m3.312s
user    0m0.064s
sys     0m0.027s
```

### mold と LLD の比較
`[3/4] SOLINK ./libvr_common.so` 相当の処理については 1.265s -> 0.563s、`[4/4] LINK ./chrome` 相当の処理については 7.777s -> 3.312s とそれぞれ **2倍以上の高速化が達成できています** 🎉

なお、上記の比較を見ると十分に早いですが、それでも「はじめにで掲載した Rui Ueyama さんの Tweet」の 2.5秒という記述に比べると遅いです。これはおそらく、今回利用した GCP VM instance の「8core」という構成に起因するのではないかと考えています。mold は複数 CPU core をうまく活用する作りになっているようなので、CPU core 数が増えることで近いパフォーマンスが出るのだと思われます。

## まとめ

Rui Ueyama さんが開発してる [mold](https://github.com/rui314/mold) を利用して、Chromium の Build をしてみました。

実験の結果、試しにリンクをするだけであれば比較的簡単に実行ができることが分かりました。また、CPU core 数が 8 とそれほど多くない構成であっても、 **LLD に比べてリンクが2倍以上高速化する** という改善が見られることが分かりました。

Rui Ueyama さんは自分が尊敬するエンジニアの1人なのですが、彼のエンジニアリングによって世界がより良くなっている事を体感できたように思います。





