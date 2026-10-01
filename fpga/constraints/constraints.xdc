# Clock
set_property PACKAGE_PIN W5 [get_ports {clock}]
	set_property IOSTANDARD LVCMOS33 [get_ports {clock}]
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock]

# Switches
set_property PACKAGE_PIN V17 [get_ports { sw_happy }]
	set_property IOSTANDARD LVCMOS33 [get_ports { sw_happy }]

# LEDS
set_property PACKAGE_PIN L1 [get_ports { LEDs[0] }]
	set_property IOSTANDARD LVCMOS33 [get_ports { LEDs[0] }]

# Switches
# set_property PACKAGE_PIN V16 [get_ports { sw_hunger }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { sw_hunger }]
# set_property PACKAGE_PIN W16 [get_ports { sw_rest }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { sw_rest }]

# Buttons
# up button
# set_property PACKAGE_PIN U18 [get_ports minigame_button]
# 	set_property IOSTANDARD LVCMOS33 [get_ports minigame_button]

# LEDs
# set_property PACKAGE_PIN V19 [get_ports { home_led }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { home_led }]
# set_property PACKAGE_PIN U16 [get_ports { happy_led }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { happy_led}]
# set_property PACKAGE_PIN E19 [get_ports { hunger_led }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { hunger_led }]
# set_property PACKAGE_PIN U19 [get_ports { rest_led }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { rest_led }]

# 7 Segment Display
# Segments
# set_property PACKAGE_PIN W7 [get_ports {seg[0]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[0]}]
# set_property PACKAGE_PIN W6 [get_ports {seg[1]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[1]}]
# set_property PACKAGE_PIN U8 [get_ports {seg[2]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[2]}]
# set_property PACKAGE_PIN V8 [get_ports {seg[3]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[3]}]
# set_property PACKAGE_PIN U5 [get_ports {seg[4]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[4]}]
# set_property PACKAGE_PIN V5 [get_ports {seg[5]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[5]}]
# set_property PACKAGE_PIN U7 [get_ports {seg[6]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {seg[6]}]
# Anodes
# set_property PACKAGE_PIN U2 [get_ports {an[0]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {an[0]}]
# set_property PACKAGE_PIN U4 [get_ports {an[1]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {an[1]}]
# set_property PACKAGE_PIN V4 [get_ports {an[2]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {an[2]}]
# set_property PACKAGE_PIN W4 [get_ports {an[3]}]
# 	set_property IOSTANDARD LVCMOS33 [get_ports {an[3]}]

# LEDS
# set_property PACKAGE_PIN L1 [get_ports { LEDs[0] }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { LEDs[0] }]
# set_property PACKAGE_PIN P1 [get_ports { LEDs[1] }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { LEDs[1]}]
# set_property PACKAGE_PIN N3 [get_ports { LEDs[2] }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { LEDs[2] }]
# set_property PACKAGE_PIN P3 [get_ports { LEDs[3] }]
# 	set_property IOSTANDARD LVCMOS33 [get_ports { LEDs[3] }]

# SWITCH
set_property PACKAGE_PIN R2 [get_ports { sw_reset }]
	set_property IOSTANDARD LVCMOS33 [get_ports { sw_reset }]

# DIFFICULTY SWITCHES
set_property PACKAGE_PIN T1 [get_ports { sw_easy }]
	set_property IOSTANDARD LVCMOS33 [get_ports { sw_easy }]
set_property PACKAGE_PIN U1 [get_ports { sw_med }]
	set_property IOSTANDARD LVCMOS33 [get_ports { sw_med }]
set_property PACKAGE_PIN W2 [get_ports { sw_hard }]
	set_property IOSTANDARD LVCMOS33 [get_ports { sw_hard }]
