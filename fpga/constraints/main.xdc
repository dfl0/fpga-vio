# Clock
set_property PACKAGE_PIN W5 [get_ports {clk}]
	set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Debug
set_property PACKAGE_PIN V17 [get_ports {rst}]
	set_property IOSTANDARD LVCMOS33 [get_ports {rst}]
set_property PACKAGE_PIN E19 [get_ports {init_error}]
	set_property IOSTANDARD LVCMOS33 [get_ports {init_error}]

# PMOD pins (IMU)
set_property PACKAGE_PIN J1 [get_ports {cs_n}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {cs_n}]
set_property PACKAGE_PIN L2 [get_ports {sck}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {sck}]
set_property PACKAGE_PIN J2 [get_ports {mosi}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {mosi}]
set_property PACKAGE_PIN G2 [get_ports {miso}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {miso}]

# PMOD pins (camera1)
# control/sync on JB
# setup pull up resistors on sio_d (does sio_c too for now)
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {sio_c}]
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {sio_d}]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {vsync}]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {href}]
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {pclk}]
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {xclk}]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {cam_reset_n}]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {cam_pwdn}]
# data on JC
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports {d[0]}]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports {d[1]}]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports {d[2]}]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports {d[3]}]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {d[4]}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {d[5]}]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports {d[6]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {d[7]}]

# Camera inputs are asynchronous to clk: pclk goes through a synchronizer,
set_false_path -from [get_ports {pclk href vsync d[*]}]


# UART pins
set_property PACKAGE_PIN A18 [get_ports {tx}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {tx}]