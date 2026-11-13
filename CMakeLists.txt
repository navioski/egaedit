cmake_minimum_required(VERSION 3.16)

project(egaedit LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build only the library; we do not need the bundled demos.
set(TV_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(TV_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(TV_OPTIMIZE_BUILD OFF CACHE BOOL "" FORCE)

add_subdirectory(vendor/tvision)

add_executable(egaedit
    src/main.cpp
    src/app.cpp
    src/dialogs.cpp
)

target_link_libraries(egaedit PRIVATE tvision)
target_include_directories(egaedit PRIVATE src)

set_target_properties(egaedit PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
