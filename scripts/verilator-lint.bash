#! /usr/bin/bash

verilator --lint-only -I./fpga/rtl/ --top-module main ./fpga/rtl/main.v --Wall