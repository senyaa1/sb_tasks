#!/bin/sh

iverilog -g2012 fb32_addsub.sv tb_fb32_addsub.sv -o fb32_addsub 
./fb32_addsub

