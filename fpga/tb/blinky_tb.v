`timescale 10ns / 100ps

module blinky_tb;

    reg clk10;
    reg dip;
    wire led;

    blinky #(.BIT_FAST(2), .BIT_SLOW(3)) dut (.clk10 (clk10), .dip (dip), .led (led));

    initial
        begin
            clk10 <= 0;
            dip <= 0;

            $dumpfile("sim/blinky.vcd");
            $dumpvars(0, blinky_tb.led, blinky_tb.dip);

            #100;
            // #100_000_000;   // 10M clock cycles = 1 second simulated
            $finish;
        end

    always
        begin
            #5  // 5 time-unit delay = 50ns => 100ns total clock period
            clk10 = ~clk10;
        end

endmodule
