#set(CMAKE_OSX_DEPLOYMENT_TARGET "10.9" CACHE STRING "Minimum macOS deployment version")
#set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "")
project(Syphon
    LANGUAGES C OBJC
    VERSION 5.0
    HOMEPAGE_URL http://syphon.v002.info/
)

if(NOT APPLE)
  message(STATUS "Syphon is not supported outside of Apple platforms")
  return()
endif()

set(CMAKE_INCLUDE_CURRENT_DIRS ON)

set(SYPHON_PUBLIC_HEADERS
  Syphon.h
  SyphonClient.h
  SyphonClientBase.h
  SyphonImage.h
  SyphonImageBase.h
  SyphonMetalClient.h
  SyphonMetalServer.h
  SyphonOpenGLClient.h
  SyphonOpenGLImage.h
  SyphonOpenGLServer.h
  SyphonServer.h
  SyphonServerBase.h
  SyphonServerDirectory.h
  SyphonSubclassing.h
)

foreach(header ${SYPHON_PUBLIC_HEADERS})
  file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/include/Syphon/${header}" INPUT "${CMAKE_CURRENT_SOURCE_DIR}/${header}")
endforeach()

add_library(Syphon STATIC
  ${SYPHON_PUBLIC_HEADERS}
  SyphonCFMessageReceiver.h
  SyphonCFMessageReceiver.m
  SyphonCFMessageSender.h
  SyphonCFMessageSender.m
  SyphonCGL.h
  SyphonCGL.c
  SyphonClient.m
  SyphonClientBase.m
  SyphonClientConnectionManager.h
  SyphonClientConnectionManager.m
  SyphonDispatch.h
  SyphonDispatch.c
  SyphonGLShader.h
  SyphonGLShader.m
  SyphonGLVertices.h
  SyphonGLVertices.m
  SyphonImage.m
  SyphonImageBase.m
  SyphonIOSurfaceImageCore.h
  SyphonIOSurfaceImageCore.m
  SyphonIOSurfaceImageLegacy.h
  SyphonIOSurfaceImageLegacy.m
  SyphonMessageQueue.h
  SyphonMessageQueue.m
  SyphonMessageReceiver.h
  SyphonMessageReceiver.m
  SyphonMessageSender.h
  SyphonMessageSender.m
  SyphonMessaging.h
  SyphonMessaging.m
  SyphonMetalClient.m
  SyphonMetalServer.m
  SyphonOpenGLClient.m
  SyphonOpenGLServer.m
  SyphonOpenGLImage.m
  SyphonOpenGLFunctions.h
  SyphonOpenGLFunctions.c
  SyphonPrivate.h
  SyphonPrivate.m
  SyphonServer.m
  SyphonServerBase.m
  SyphonServerConnectionManager.h
  SyphonServerConnectionManager.m
  SyphonServerDirectory.m
  SyphonServerGLShader.h
  SyphonServerGLShader.m
  SyphonServerGLVertices.h
  SyphonServerGLVertices.m
  SyphonServerMetalTypes.h
  SyphonServerRendererCoreGL.h
  SyphonServerRendererCoreGL.m
  SyphonServerRendererGL.h
  SyphonServerRendererGL.m
  SyphonServerRendererLegacyGL.h
  SyphonServerRendererLegacyGL.m
  SyphonServerRendererMetal.h
  SyphonServerRendererMetal.m
  SyphonMetalShaders.metal
)

# Export SYPHON_METALLIB path for parent to bundle
if(${CMAKE_GENERATOR} MATCHES "^Xcode.*")
  set_source_files_properties(SyphonMetalShaders.metal PROPERTIES LANGUAGE METAL)
  set(SYPHON_METALLIB "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/default.metallib" PARENT_SCOPE)
else()
  # Ninja cannot compile Metal shaders, copy the precompiled metallib
  add_custom_command(TARGET Syphon POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/default.metallib"
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/>"
  )
  set(SYPHON_METALLIB "${CMAKE_CURRENT_BINARY_DIR}/default.metallib" PARENT_SCOPE)
endif()

target_compile_options(Syphon PRIVATE "-fobjc-arc")

target_precompile_headers(Syphon PUBLIC "Syphon_Prefix.pch")

target_include_directories(Syphon PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>")
target_compile_definitions(Syphon PRIVATE SYPHON_CORE_SHARE)

target_link_libraries(Syphon PRIVATE
    "-framework OpenGL"
    "-framework Metal"
    "-framework Cocoa"
    "-framework IOSurface"
)