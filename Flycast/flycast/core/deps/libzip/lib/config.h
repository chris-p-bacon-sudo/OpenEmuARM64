#ifndef HAD_CONFIG_H
#define HAD_CONFIG_H
#ifndef _HAD_ZIPCONF_H
#include "zipconf.h"
#endif

/*
   config.h -- libzip platform configuration for macOS (arm64)

   This file was generated as a static replacement for the
   CMake-generated version. Based on cmake-config.h.in.
   CMake feature-detection results for macOS / Darwin / Apple Clang.
*/

/* macOS has arc4random() */
#define HAVE_ARC4RANDOM 1

/* macOS 10.12+ has clonefile() */
#define HAVE_CLONEFILE 1

/* macOS has CommonCrypto */
#define HAVE_COMMONCRYPTO 1

/* Standard POSIX/macOS functions */
#define HAVE_FILENO 1
#define HAVE_FCHMOD 1
#define HAVE_FSEEKO 1
#define HAVE_FTELLO 1
#define HAVE_GETPROGNAME 1
#define HAVE_LOCALTIME_R 1
#define HAVE_MKSTEMP 1
#define HAVE_SNPRINTF 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1

/* Clang supports nullable annotations natively */
#define HAVE_NULLABLE 1

/* tm_zone field in struct tm is available on macOS */
#define HAVE_STRUCT_TM_TM_ZONE 1

/* Standard headers present */
#define HAVE_STDBOOL_H 1
#define HAVE_STRINGS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_DIRENT_H 1
#define HAVE_FTS_H 1

/* off_t and size_t are 64-bit on macOS arm64 */
#define SIZEOF_OFF_T 8
#define SIZEOF_SIZE_T 8

#define PACKAGE "libzip"
#define VERSION "1.10.1"

#endif /* HAD_CONFIG_H */
