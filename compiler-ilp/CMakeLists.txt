cmake_minimum_required(VERSION 3.18)
project(pipelining LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ortools CONFIG REQUIRED)
find_package(GTest REQUIRED)

set(SOURCE_FILES 
	src/solver.cpp
)

add_executable(pipelining ${SOURCE_FILES} src/main.cpp)

target_link_libraries(pipelining PRIVATE ortools::ortools)

add_executable(pipelining_test ${SOURCE_FILES} src/tests.cpp)
target_link_libraries(pipelining_test PRIVATE ortools::ortools GTest::gtest GTest::gtest_main)
