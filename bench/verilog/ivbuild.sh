#!/bin/bash

iverilog -g2012 -I ../../rtl -c sim_files.txt -s satatb_top
