#!/bin/sh


mkdir -p build
pushd .
cd build
cmake ..
cmake --build .
popd
