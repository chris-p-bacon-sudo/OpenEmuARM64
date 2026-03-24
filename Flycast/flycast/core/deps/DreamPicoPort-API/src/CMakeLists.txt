cmake_minimum_required(VERSION 3.16)

set(CMAKE_VERBOSE_MAKEFILE ON)

file(GLOB SRC "${CMAKE_CURRENT_SOURCE_DIR}/*.c*")

if (DREAMPICOPORT_API_BUILD_SHARED_LIBS)
  add_library(dream_pico_port_api SHARED ${SRC})
  if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    target_compile_definitions(dream_pico_port_api
        INTERFACE
            "WIN32_DREAM_PICO_PORT_IMPORTS"
        PRIVATE
            "WIN32_DREAM_PICO_PORT_EXPORTS"
    )
  endif()
else()
  add_library(dream_pico_port_api STATIC ${SRC})
endif()

if (DREAMPICOPORT_WITH_LIBUSB)
  target_link_libraries(dream_pico_port_api
    PRIVATE
      ${DREAMPICOPORT_LIBUSB_LIBRARIES}
  )

  target_include_directories(dream_pico_port_api
    PRIVATE
      ${DREAMPICOPORT_LIBUSB_INCLUDE_DIRS}
  )

else()

  target_compile_definitions(dream_pico_port_api PRIVATE DREAMPICOPORT_NO_LIBUSB)
  target_link_libraries(dream_pico_port_api PRIVATE WindowsApp)

endif()

# For the most part, this lib is C++11 compatible, but std::make_unique() is used which is C++14
# I'm choosing C++17 just because C++14 was less adopted so may as well go to the next notch
set_target_properties(dream_pico_port_api PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

target_include_directories(dream_pico_port_api
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>")

install(
    TARGETS
        dream_pico_port_api
    EXPORT
        dream_pico_port_api
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}" COMPONENT Development
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}" COMPONENT Development
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}" COMPONENT Development
)
if((BUILD_SHARED_LIBS) AND (CMAKE_SYSTEM_NAME STREQUAL "Windows"))
    set_target_properties(dream_pico_port_api
        PROPERTIES
            VS_DEBUGGER_ENVIRONMENT
            "PATH=${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}"
    )

    install(
        FILES
            "$<TARGET_PDB_FILE:dream_pico_port_api>"
        DESTINATION
            "${CMAKE_INSTALL_BINDIR}"
        COMPONENT Development
        OPTIONAL
    )
endif()
install(
    DIRECTORY
        "${CMAKE_CURRENT_SOURCE_DIR}/"
    DESTINATION
        "${CMAKE_INSTALL_INCLUDEDIR}/dream_pico_port_api"
    COMPONENT Development
    FILES_MATCHING PATTERN
        "DreamPicoPortApi.hpp"
)
