module main(
    input clk, // clk

    // debug
    input rst, // v17
    output reg valid, // u16
    output reg init_error, // e19

    // icm20948
    output wire cs_n,
    output wire sck,
    output wire mosi,
    input wire miso,

    // sseg
    output reg [3:0] anode,
    output reg [6:0] seg_out
);

    reg [7:0] accel_y_h;
    reg [16:0] display_value;
    
    assign display_value = {8'b0, accel_y_h};
    
    icm20948_controller imu (
        .*
    );

    sseg display (
        .*
    );

endmodule