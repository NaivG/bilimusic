cmake_minimum_required(VERSION 3.4.1)

# 设置Oboe库路径
set(OBOE_DIR ../../../../../../oboe)
set(OBOE_INCLUDE_DIR ${OBOE_DIR}/include)

# 创建库
add_library(just_aaudio SHARED
    native-audio.cpp)

# 添加Oboe库
add_subdirectory(${OBOE_DIR} ./oboe)

# 包含头文件目录
target_include_directories(just_aaudio PRIVATE
    ${OBOE_INCLUDE_DIR})

# 链接库
target_link_libraries(just_aaudio
    oboe
    log)