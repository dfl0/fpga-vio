`timescale 1ns/1ps

module main (
    input wire clk,

    // debug
    input wire rst, // v17
    output reg sample_seen, // u16
    output wire init_error, // e19

    // icm20948
    output wire cs_n,
    output wire sck,
    output wire mosi,
    input wire miso,

    // sseg
    output wire [3:0] anode,
    output wire [6:0] seg_out,
    output wire dp
);

    wire [7:0] accel_y_h;
    wire sample_valid;
    wire [15:0] display_value;

    assign display_value = {8'b0, accel_y_h};
    assign dp = 1'b1; // active-low decimal point, off

    // latch controller's one clock wide valid signal to see it on the LED
    always @(posedge clk) begin
        if (rst)
            sample_seen <= 1'b0;
        else if (sample_valid)
            sample_seen <= 1'b1;
    end

    icm20948_controller imu (
        .clk(clk),
        .rst(rst),
        .accel_y_h(accel_y_h),
        .valid(sample_valid),
        .init_error(init_error),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );

    sseg display (
        .clk(clk),
        .rst(rst),
        .display_value(display_value),
        .anode(anode),
        .seg_out(seg_out)
    );

endmodule
