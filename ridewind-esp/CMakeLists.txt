cmake_minimum_required(VERSION 3.16)

# 锁定目标芯片为 ESP32-S3（硬件实际使用的芯片）
set(IDF_TARGET "esp32s3" CACHE STRING "Target chip")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(ridewind-esp)
