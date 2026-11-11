dnl
dnl  macosx_redesign: the redesigned macOS interface (redesign/docs/ARCHITECTURE.md §7.4)
dnl
dnl  m4_include'd from configure.ac right after the minimal_macosx block, so enable_macosx and
dnl  with_sanitizer are known here. After editing this file, rerun ./bootstrap (or let the
dnl  Makefile's autoconf rerun rule do it) and reconfigure.
dnl
AC_ARG_ENABLE([macosx-redesign],
  AS_HELP_STRING([--enable-macosx-redesign],
    [redesigned macOS interface; replaces the stock one, needs --disable-macosx (default disabled)]))
AC_ARG_WITH([macosx-redesign-bundle-id],
  AS_HELP_STRING([--with-macosx-redesign-bundle-id=ID],
    [bundle identifier of the packaged app (default io.github.lemelson.vlc-redesign)]),
  [], [with_macosx_redesign_bundle_id="io.github.lemelson.vlc-redesign"])
AC_ARG_WITH([macosx-redesign-app-name],
  AS_HELP_STRING([--with-macosx-redesign-app-name=NAME],
    [name of the packaged app in the menu bar and Finder (default "VLC Redesign")]),
  [], [with_macosx_redesign_app_name="VLC Redesign"])

dnl configure.ac's darwin block appends -isysroot and -mmacosx-version-min to CC, CXX, OBJC and
dnl OBJCXX, but LT_INIT runs later, and libtool 2.5+ (extras/tools ships 2.6.2) configures its
dnl Objective-C tags with AC_CHECK_TOOL, which resets OBJC and OBJCXX to the cached bare compiler.
dnl Every .m file (bin/darwinvlc.m, the AVFoundation/CoreAnimation/notification plugins) was then
dnl compiled and linked without a deployment target and required the SDK's macOS (27.2 for the
dnl 1.0.0 and 1.0.1 releases, GitHub issue #2). Put the flags back where they are missing.
AS_IF([test "${SYS}" = "darwin"], [
  AS_IF([test -n "${with_macosx_sdk}"], [
    AS_CASE([" ${OBJC} "], [*" -isysroot "*], [], [OBJC="${OBJC} -isysroot ${with_macosx_sdk}"])
    AS_CASE([" ${OBJCXX} "], [*" -isysroot "*], [], [OBJCXX="${OBJCXX} -isysroot ${with_macosx_sdk}"])
  ])
  AS_IF([test -n "${with_macosx_version_min}"], [
    AS_CASE([" ${OBJC} "], [*" -mmacosx-version-min="*], [],
      [OBJC="${OBJC} -mmacosx-version-min=${with_macosx_version_min}"])
    AS_CASE([" ${OBJCXX} "], [*" -mmacosx-version-min="*], [],
      [OBJCXX="${OBJCXX} -mmacosx-version-min=${with_macosx_version_min}"])
  ])
])

MXR_MIN_MACOS="14.0"
MXR_SDK_PATH=""
MXR_SWIFT_TOOLCHAIN_LIBDIR=""
MXR_SWIFT_ARCH=""
MXR_SWIFT_CONFIGURATION="release"
MXR_SANITIZER=""

AS_IF([test "${enable_macosx_redesign}" = "yes"], [
  AS_IF([test "${SYS}" != "darwin"],
    [AC_MSG_ERROR([--enable-macosx-redesign requires macOS])])
  AS_IF([test "${enable_macosx}" != "no"],
    [AC_MSG_ERROR([--enable-macosx-redesign replaces the stock interface; add --disable-macosx])])

  AC_PATH_PROG([MXR_XCRUN], [xcrun], [no])
  AS_IF([test "${MXR_XCRUN}" = "no"], [AC_MSG_ERROR([xcrun not found: install Xcode 16 or newer])])

  AC_MSG_CHECKING([for Swift 6 or newer])
  mxr_swift_major="$(${MXR_XCRUN} swift --version 2>/dev/null | sed -n 's/.*Swift version \([[0-9]]*\)\..*/\1/p' | head -n 1)"
  AS_IF([test -n "${mxr_swift_major}" && test "${mxr_swift_major}" -ge 6],
    [AC_MSG_RESULT([yes (${mxr_swift_major})])],
    [AC_MSG_RESULT([no])
     AC_MSG_ERROR([the macosx_redesign interface needs a Swift 6 toolchain (Xcode 16 or newer)])])

  AS_IF([test -n "${with_macosx_sdk}"],
    [MXR_SDK_PATH="${with_macosx_sdk}"],
    [MXR_SDK_PATH="$(${MXR_XCRUN} --sdk macosx --show-sdk-path 2>/dev/null)"])
  AS_IF([test ! -d "${MXR_SDK_PATH}/usr/lib/swift"],
    [AC_MSG_ERROR([no Swift libraries in the macOS SDK "${MXR_SDK_PATH}"])])

  mxr_swift_bin="$(${MXR_XCRUN} -f swift 2>/dev/null)"
  MXR_SWIFT_TOOLCHAIN_LIBDIR="$(dirname "${mxr_swift_bin}")/../lib/swift/macosx"

  AS_CASE([${host_cpu}],
    [aarch64|arm64], [MXR_SWIFT_ARCH="arm64"],
    [x86_64], [MXR_SWIFT_ARCH="x86_64"],
    [AC_MSG_ERROR([unsupported architecture for the macosx_redesign interface: ${host_cpu}])])

  dnl Swift is always optimized (+ -g); override per build with make MXR_SWIFT_CONFIGURATION=debug.
  AS_IF([test "${with_sanitizer}" != "no" && test -n "${with_sanitizer}"],
    [MXR_SANITIZER="${with_sanitizer}"])
])

AC_SUBST([MXR_MIN_MACOS])
AC_SUBST([MXR_SDK_PATH])
AC_SUBST([MXR_SWIFT_TOOLCHAIN_LIBDIR])
AC_SUBST([MXR_SWIFT_ARCH])
AC_SUBST([MXR_SWIFT_CONFIGURATION])
AC_SUBST([MXR_SANITIZER])
AC_SUBST([MXR_BUNDLE_ID], ["${with_macosx_redesign_bundle_id}"])
AC_SUBST([MXR_APP_NAME], ["${with_macosx_redesign_app_name}"])
AM_CONDITIONAL([ENABLE_MACOSX_REDESIGN], [test "${enable_macosx_redesign}" = "yes"])
