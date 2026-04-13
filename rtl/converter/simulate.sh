#!/bin/sh

iverilog -g2012 fp32converter.sv tb_fp32converter.sv -o fb32converter
./fb32converter

