#pragma once

#define GIT_BRANCH "master"
#define GIT_TAG "r8-39"
#define GIT_COMMIT_HASH "f1d3b80"
#define GIT_COMMIT_DATE "2020-12-24"

#define CORE_BASE_NAME "angrylion's RDP Plus"

#ifdef _DEBUG
#define CORE_NAME CORE_BASE_NAME " " GIT_TAG " (Debug)"
#else
#define CORE_NAME CORE_BASE_NAME " " GIT_TAG
#endif

#define CORE_SIMPLE_NAME "angrylion-plus"
