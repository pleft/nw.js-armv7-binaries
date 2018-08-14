#!/bin/sh

sudo apt-get update -qq
sudo apt-get upgrade -qq
sudo apt-get install git curl htop sysstat openssh-server python -qq

git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH=$PATH:"$(pwd)"/depot_tools

mkdir -p "$(pwd)"/nwjs
export NWJS="$(pwd)"/nwjs
cd $NWJS

# get default branch of NW.js
# export DEFAULT_BRANCH="$(curl https://api.github.com/repos/nwjs/nw.js | grep -Po '(?<="default_branch": ")[^"]*')"

DEFAULT_BRANCH=nw28

gclient config --name=src https://github.com/nwjs/chromium.src.git@origin/"${DEFAULT_BRANCH}"

# export MAGIC='"src/third_party/WebKit/LayoutTests": None, "src/chrome_frame/tools/test/reference_build/chrome": None, "src/chrome_frame/tools/test/reference_build/chrome_win": None, "src/chrome/tools/test/reference_build/chrome": None, "src/chrome/tools/test/reference_build/chrome_linux": None, "src/chrome/tools/test/reference_build/chrome_mac": None, "src/chrome/tools/test/reference_build/chrome_win": None,'

# awk -v values="${MAGIC}" '/custom_deps/ { print; print values; next }1' .gclient | cat > .gclient.temp
# mv .gclient.temp .gclient

# replace custom_deps manually with:

# "custom_deps" : {
#     "src/third_party/WebKit/LayoutTests": None,
#     "src/chrome_frame/tools/test/reference_build/chrome": None,
#     "src/chrome_frame/tools/test/reference_build/chrome_win": None,
#     "src/chrome/tools/test/reference_build/chrome": None,
#     "src/chrome/tools/test/reference_build/chrome_linux": None,
#     "src/chrome/tools/test/reference_build/chrome_mac": None,
#     "src/chrome/tools/test/reference_build/chrome_win": None,
# }

# clone some stuff
mkdir -p $NWJS/src/content/nw
mkdir -p $NWJS/src/third_party/node-nw
mkdir -p $NWJS/src/v8
git clone https://github.com/nwjs/nw.js $NWJS/src/content/nw
git clone https://github.com/nwjs/node $NWJS/src/third_party/node-nw
git clone https://github.com/nwjs/v8 $NWJS/src/v8

git fetch --tags --prune
git reset --hard HEAD
git checkout "${DEFAULT_BRANCH}"

cd $NWJS/src/content/nw
git fetch --tags --prune
git checkout "${DEFAULT_BRANCH}"
cd $NWJS/src/third_party/node-nw
git fetch --tags --prune
git checkout "${DEFAULT_BRANCH}"
cd $NWJS/src/v8
git fetch --tags --prune
git checkout "${DEFAULT_BRANCH}"

cd $NWJS/src
export GYP_CROSSCOMPILE="1"
export GYP_DEFINES="is_debug=false is_component_ffmpeg=true target_arch=arm target_cpu=\"arm\" arm_float_abi=hard"
export GN_ARGS="nwjs_sdk=false enable_nacl=false ffmpeg_branding=\"Chrome\"" #

export GYP_CHROMIUM_NO_ACTION=1
gclient sync --reset --with_branch_heads --nohooks

./build/install-build-deps.sh --arm

# ---------------------------------------
# Get and apply patches from @jtg-gg
# ---------------------------------------

# [Build] add node build tools for linux arm
curl -s https://github.com/jtg-gg/chromium.src/commit/65f2215706692e438ca3570be640ed724ae37eaf.patch | git am &&
# [Build][gn] add support for linux arm binary strip
curl -s https://github.com/jtg-gg/chromium.src/commit/2a3ca533a4dd2552889bd18cd4343809f13876c4.patch | git am &&
cd $NWJS/src/content/nw/ &&
# [Build] add patches for Linux arm build
curl -s https://github.com/jtg-gg/node-webkit/commit/76770752e362b83b127ac4bf3aacc0c9a81bd590.patch | git am &&
# [Build][Linux] add support for linux arm binary strip and packaging
curl -s https://github.com/jtg-gg/node-webkit/commit/a59ff4c4f7ede3b47411719e41c59332b25b7259.patch | git am &&
# [Build] remove ffmpeg patch
curl -s https://github.com/jtg-gg/node-webkit/commit/11dcb9c775e43c78eb8136148e23ffe3b15d737e.patch | git am &&
# [Build] fixes :
curl -s https://github.com/jtg-gg/node-webkit/commit/c87b16766cda3f0af1ffa76b2b24390d77a005e0.patch | git am &&
# [Build][Symbols] put nwjs version and commit-id into crash report, zi
curl -s https://github.com/jtg-gg/node-webkit/commit/d480e6dcf6e49fd64200fd347d406554e76ef72e.patch | git am &&
# [Build] debug runtime fixes
curl -s https://github.com/jtg-gg/node-webkit/commit/42e15aeaf9b47447023d866fd94c82774327c49b.patch | git am

cd $NWJS/src &&
gclient runhooks &&
gn gen out_gn_arm/nw --args="$GN_ARGS" &&
export GYP_CHROMIUM_NO_ACTION=0 &&
python build/gyp_chromium -Goutput_dir=out_gn_arm -I third_party/node-nw/build/common.gypi third_party/node-nw/node.gyp

# Build
ninja -C out_gn_arm/nw nwjs &&
ninja -C out_gn_arm/nw v8_libplatform &&
ninja -C out_gn_arm/Release node &&
ninja -C out_gn_arm/nw copy_node &&
ninja -C out_gn_arm/nw dump &&
ninja -C out_gn_arm/nw dist
