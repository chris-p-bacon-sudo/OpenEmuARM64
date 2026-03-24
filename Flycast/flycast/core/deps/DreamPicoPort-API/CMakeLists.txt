cmake_minimum_required(VERSION 3.16)

project(dream_pico_port_api
    DESCRIPTION "API for DreamPicoPort hardware"
    VERSION "1.0.3"
    LANGUAGES CXX
)

option(DREAMPICOPORT_API_BUILD_SHARED_LIBS "Build Shared Libraries for DreamPicoPort-API" OFF)
option(DREAMPICOPORT_TESTS "Build tests executable for DreamPicoPort" OFF)

# Setting DREAMPICOPORT_WITH_LIBUSB to OFF is only valid on Windows.
# When DREAMPICOPORT_WITH_LIBUSB is OFF, winrt is used which is compatible with UWP.
option(DREAMPICOPORT_WITH_LIBUSB "Use libusb to access DreamPicoPort-API" ON)

if (DREAMPICOPORT_WITH_LIBUSB)
    set(DREAMPICOPORT_LIBUSB_LIBRARIES "usb-1.0" CACHE STRING "Name of the libusb library to link against")
    set(DREAMPICOPORT_LIBUSB_INCLUDE_DIRS "" CACHE STRING "Path to libusb include directory, when applicable")
    option(DREAMPICOPORT_USE_EXTERNAL_LIBUSB "Locate libusb using find_package" OFF)
    set(DREAMPICOPORT_EXTERNAL_LIBUSB_PROJECT_NAME "libusb" CACHE STRING "Name of the external libusb project when DREAMPICOPORT_USE_EXTERNAL_LIBUSB is true")

    if (DREAMPICOPORT_USE_EXTERNAL_LIBUSB)
        # Use external build of libusb
        find_package(${DREAMPICOPORT_EXTERNAL_LIBUSB_PROJECT_NAME} REQUIRED)
        message(STATUS "${DREAMPICOPORT_EXTERNAL_LIBUSB_PROJECT_NAME}: ${${DREAMPICOPORT_EXTERNAL_LIBUSB_PROJECT_NAME}_DIR}")
    else()
        # Build from a local libusb
        option(DREAMPICOPORT_ADD_LIBUSB "Add internal libusb library" ON)

        if(DREAMPICOPORT_ADD_LIBUSB)
            option(LIBUSB_BUILD_SHARED_LIBS ${DREAMPICOPORT_API_BUILD_SHARED_LIBS})
            add_subdirectory("ext/libusb-cmake/")
        else()
            message(STATUS "Skipping include of cmake-libusb")
        endif()
    endif()
endif()

add_subdirectory("src")

if (DREAMPICOPORT_TESTS)
    add_subdirectory("test")
endif()
