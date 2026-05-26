cmake_minimum_required(VERSION 3.22.1)

project("just_aaudio")

# 添加Oboe库
find_package(oboe REQUIRED CONFIG)

# 下载并构建libsndfile
include(FetchContent)

set(BUILD_SHARED_LIBS OFF)
set(BUILD_PROGRAMS OFF)
set(BUILD_EXAMPLES OFF)
set(BUILD_TESTING OFF)
set(ENABLE_EXTERNAL_LIBS OFF)

FetchContent_Declare(
    sndfile
    GIT_REPOSITORY https://github.com/libsndfile/libsndfile.git
    GIT_TAG 1.2.2
)

FetchContent_MakeAvailable(sndfile)

# 创建原生库
add_library(
    ${CMAKE_PROJECT_NAME}
    SHARED
    src/main/cpp/native-audio.cpp
)

# 链接库
target_link_libraries(
    ${CMAKE_PROJECT_NAME}
    oboe::oboe
    sndfile
    log
)