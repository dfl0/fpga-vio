#! /usr/bin/bash

verilator --lint-only -Wall --top-module main $(find ./fpga/rtl -name "*.v")