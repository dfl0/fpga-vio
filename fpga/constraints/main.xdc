# Clock
set_property PACKAGE_PIN W5 [get_ports {clk}]
	set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]


# Debug
set_property PACKAGE_PIN V17 [get_ports {rst}]
	set_property IOSTANDARD LVCMOS33 [get_ports {rst}]
set_property PACKAGE_PIN U16 [get_ports {sample_seen}]
	set_property IOSTANDARD LVCMOS33 [get_ports {sample_seen}]
set_property PACKAGE_PIN E19 [get_ports {init_error}]
	set_property IOSTANDARD LVCMOS33 [get_ports {init_error}]

# PMOD pins
set_property PACKAGE_PIN J1 [get_ports {cs_n}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {cs_n}]
set_property PACKAGE_PIN L2 [get_ports {sck}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {sck}]
set_property PACKAGE_PIN J2 [get_ports {mosi}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {mosi}]
set_property PACKAGE_PIN G2 [get_ports {miso}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {miso}]


# 7 Segment Display
# Segments: seg_out[6:0] = {a,b,c,d,e,f,g}, active low
set_property PACKAGE_PIN W7 [get_ports {seg_out[6]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[6]}]
set_property PACKAGE_PIN W6 [get_ports {seg_out[5]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[5]}]
set_property PACKAGE_PIN U8 [get_ports {seg_out[4]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[4]}]
set_property PACKAGE_PIN V8 [get_ports {seg_out[3]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[3]}]
set_property PACKAGE_PIN U5 [get_ports {seg_out[2]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[2]}]
set_property PACKAGE_PIN V5 [get_ports {seg_out[1]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[1]}]
set_property PACKAGE_PIN U7 [get_ports {seg_out[0]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {seg_out[0]}]
set_property PACKAGE_PIN V7 [get_ports {dp}]
	set_property IOSTANDARD LVCMOS33 [get_ports {dp}]
# Anodes
set_property PACKAGE_PIN U2 [get_ports {anode[0]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {anode[0]}]
set_property PACKAGE_PIN U4 [get_ports {anode[1]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {anode[1]}]
set_property PACKAGE_PIN V4 [get_ports {anode[2]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {anode[2]}]
set_property PACKAGE_PIN W4 [get_ports {anode[3]}]
	set_property IOSTANDARD LVCMOS33 [get_ports {anode[3]}]
