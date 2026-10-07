module main(
    input clk, // clk

    // debug
    input rst, // v17
    output wire valid, // u16
    output wire init_error, // e19

    // icm20948
    output wire cs_n,
    output wire sck,
    output wire mosi,
    input wire miso,

    // sseg
    output wire [3:0] anode,
    output wire [6:0] seg_out
);

    reg [7:0] accel_y_h;
    wire [16:0] display_value;
    
    assign display_value = {8'b0, accel_y_h};
    
    icm20948_controller imu (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .init_error(init_error),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );

    sseg display (
        .clk(clk),
        .display_value(display_value),
        .anode(anode),
        .seg_out(seg_out)
    );

endmodule