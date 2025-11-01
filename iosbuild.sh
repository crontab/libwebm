#!/bin/sh
##
##  Copyright (c) 2015 The WebM project authors. All Rights Reserved.
##
##  Use of this source code is governed by a BSD-style license
##  that can be found in the LICENSE file in the root of the source
##  tree. An additional intellectual property rights grant can be found
##  in the file PATENTS.  All contributing project authors may
##  be found in the AUTHORS file in the root of the source tree.
##
## This script generates 'WebM.framework'. An iOS app can mux/demux WebM
## container files by including 'WebM.framework'.
##
## Run ./iosbuild.sh to generate 'WebM.framework'. By default the framework
## bundle will be created in a directory called framework. Use --out-dir to
## change the output directory.
##
## This script is based on iosbuild.sh from the libwebp project.
. $(dirname $0)/common/common.sh

# Trap function. Cleans up build output.
cleanup() {
  local readonly res=$?
  cd "${ORIG_PWD}"

  for dir in ${LIBDIRS}; do
    if [ -d "${dir}" ]; then
      rm -rf "${dir}"
    fi
  done

  if [ $res -ne 0 ]; then
    elog "build exited with error ($res)"
  fi
}

trap cleanup EXIT

check_dir libwebm

iosbuild_usage() {
cat << EOF
  Usage: ${0##*/} [arguments]
    --help: Display this message and exit.
    --out-dir: Override output directory (default is ${OUTDIR}).
    --show-build-output: Show output from each library build.
    --verbose: Output information about the environment and each stage of the
               build.
EOF
}

# Extract the latest SDK version from the final field of the form: iphoneosX.Y
readonly SDK=$(xcodebuild -showsdks \
  | grep iphoneos | sort | tail -n 1 | awk '{print substr($NF, 9)}'
)

# Extract Xcode version.
readonly XCODE=$(xcodebuild -version | grep Xcode | cut -d " " -f2)
if [ -z "${XCODE}" ]; then
  echo "Xcode not available"
  exit 1
fi

# Add iPhoneOS-V6 to the list of platforms below if you need armv6 support.
# Note that iPhoneOS-V6 support is not available with the iOS6 SDK.
readonly INCLUDES="common/file_util.h
                   common/hdr_util.h
                   common/webmids.h
                   mkvmuxer/mkvmuxer.h
                   mkvmuxer/mkvmuxertypes.h
                   mkvmuxer/mkvmuxerutil.h
                   mkvmuxer/mkvwriter.h
                   mkvparser/mkvparser.h
                   mkvparser/mkvreader.h"
readonly PLATFORMS="iphoneos iphonesimulator"
readonly DEVELOPER="$(xcode-select --print-path)"
readonly PLATFORMSROOT="${DEVELOPER}/Platforms"
readonly LIPO="$(xcrun -sdk iphoneos${SDK} -find lipo)"
LIBLIST=""
OPT_FLAGS="-DNDEBUG -O3"
readonly SDK_MAJOR_VERSION="$(echo ${SDK} | awk -F '.' '{ print $1 }')"

if [ -z "${SDK_MAJOR_VERSION}" ]; then
  elog "iOS SDK not available"
  exit 1
elif [ "${SDK_MAJOR_VERSION}" -lt "6" ]; then
  elog "You need iOS SDK version 6 or above"
  exit 1
else
  vlog "iOS SDK Version ${SDK}"
fi


# Parse the command line.
while [ -n "$1" ]; do
  case "$1" in
    --help)
      iosbuild_usage
      exit
      ;;
    --out-dir)
      OUTDIR="$2"
      shift
      ;;
    --enable-debug)
      OPT_FLAGS="-g"
      ;;
    --show-build-output)
      devnull=
      ;;
    --verbose)
      VERBOSE=yes
      ;;
    *)
      iosbuild_usage
      exit 1
      ;;
  esac
  shift
done

readonly OPT_FLAGS="${OPT_FLAGS}"
readonly OUTDIR="${OUTDIR:-framework}"

if [ "${VERBOSE}" = "yes" ]; then
cat << EOF
  OUTDIR=${OUTDIR}
  INCLUDES=${INCLUDES}
  PLATFORMS=${PLATFORMS}
  DEVELOPER=${DEVELOPER}
  LIPO=${LIPO}
  OPT_FLAGS=${OPT_FLAGS}
  ORIG_PWD=${ORIG_PWD}
EOF
fi

# Build each platform separately then merge everything into a xcframework. Is there a shorter way?
for PLATFORM in ${PLATFORMS}; do
  ARCH2=""
  if [ "${PLATFORM}" = "iphoneos" ]; then
    ARCH="aarch64"
    TARGET_ARCH="arm64-apple-ios18.0"
  elif [ "${PLATFORM}" = "iphonesimulator" ]; then
    ARCH="x86_64"
    TARGET_ARCH="arm64-apple-ios18.0-simulator"
  else
    echo "Invalid architecture"
    exit
  fi

  TARGETDIR="${OUTDIR}/WebM-${PLATFORM}.framework"

  rm -rf "${TARGETDIR}"

  # Copy public headers
  mkdir -p "${TARGETDIR}/Headers/"
  framework_header_dir="${TARGETDIR}/Headers"
  framework_header_sub_dirs="common mkvmuxer mkvparser"
  for dir in ${framework_header_sub_dirs}; do
    mkdir "${framework_header_dir}/${dir}"
  done
  for header_file in ${INCLUDES}; do
    eval cp -p ${header_file} "${framework_header_dir}/${header_file}" ${devnull}
  done

  LIBDIR="${OUTDIR}/${PLATFORM}-${SDK}-${ARCH}"
  LIBDIRS="${LIBDIRS} ${LIBDIR}"
  LIBFILE="${LIBDIR}/libwebm.a"
  eval mkdir -p "${LIBDIR}" ${devnull}

  DEVROOT="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain"
  SDKROOT="${PLATFORMSROOT}/"
  SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
  CXXFLAGS="-target ${TARGET_ARCH} -isysroot ${SDKROOT} ${OPT_FLAGS}"

  # Build using the legacy makefile (instead of generating via cmake).
  eval make -f Makefile.unix libwebm.a CXXFLAGS=\"${CXXFLAGS}\" ${devnull}

  # copy lib and add it to LIBLIST.
  eval cp libwebm.a "${LIBFILE}" ${devnull}

  FWFILE="${TARGETDIR}/WebM-${PLATFORM}"
  eval ${LIPO} -create ${LIBFILE} -output ${FWFILE} ${devnull}

  FWDIRS="${FWDIRS} ${TARGETDIR}"
  FWOPTS="${FWOPTS} -framework ${TARGETDIR}"

  # clean build so we can go again.
  eval make -f Makefile.unix clean ${devnull}
done

eval xcodebuild -create-xcframework ${FWOPTS} -output "${OUTDIR}/WebM.xcframework" ${devnull}

rm -rf ${FWDIRS}

echo "Succesfully built WebM.xcframework."
