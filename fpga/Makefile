# RTL simulation with Icarus Verilog
#
# Requires: GNU make, iverilog, vvp; surfer for wave (or set VIEWER).
# Sources:  rtl/<name>.v and tb/<name>_tb.v.
# Each testbench must write sim/<name>.vcd.
#
# From fpga/:
#   make sim TB=<name>             Run one testbench.
#   make wave TB=<name>  		   Run and view its VCD.
#   make wave TB=<name> VIEWER=... Use a different VCD viewer (default: surfer).
#   make all               		   Run all testbenches.
#   make clean             		   Remove sim/.

SRC   := $(wildcard rtl/*.v)
ALLTB := $(patsubst tb/%_tb.v,%,$(wildcard tb/*_tb.v))
VIEWER ?= surfer

.PHONY: sim wave all clean check-tb

check-tb:
ifndef TB
	$(error TB is not set. Usage: make TB=<name> [wave])
endif

sim: check-tb sim/$(TB).vcd

sim/$(TB).out: $(SRC) tb/$(TB)_tb.v
	@mkdir -p sim
	iverilog -g2012 -Wall -o $@ $^

sim/$(TB).vcd: sim/$(TB).out
	vvp $<

wave: sim
	$(VIEWER) sim/$(TB).vcd

all:
	@for t in $(ALLTB); do $(MAKE) --no-print-directory sim TB=$$t || exit 1; done

clean:
	rm -rf sim
