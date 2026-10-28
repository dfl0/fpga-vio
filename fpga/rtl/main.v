`timescale 1ns/1ps

module main (
    input wire clk,

    // debug
    input wire rst, // V17
    output wire init_error, // E19
    
    // uart
    output wire tx,

    // icm20948
    output wire cs_n,  // JA1 -> CS
    output wire sck,   // JA2 -> SCL
    output wire mosi,  // JA3 -> SDA
    input wire miso,   // JA4 ->SDO

    // sseg
    output wire [3:0] anode,
    output wire [6:0] seg_out,
    output wire dp
);

    // internal
    wire signed [15:0] accel_x;
    wire [7:0] uart_data;

    icm20948_controller imu (
        .clk(clk),
        .rst(rst),
        .accel_x(accel_x),
        .accel_y(),
        .accel_z(),
        .gyro_x(),
        .gyro_y(),
        .gyro_z(),
        .valid(),
        .init_error(init_error),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );
    
    uart_controller uart(
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .data(uart_data)
    );

    // START DISPLAY CODE
    // NORMAL FREQ
    // wire [15:0] display_value;
    // assign display_value = accel_x;
    // assign dp = 1'b1; // active-low decimal point, off

    // LOWER FREQ DISPLAY FOR DEBUG
    reg [15:0] display_value;
    reg [30:0] delay;
    always @(posedge clk) begin
        if (rst) begin
            delay <= 0;
        end else begin
            if (delay == 0) begin
                display_value <= accel_x;
            end else begin
                delay <= delay + 1;
            end
        end
    end

    sseg display (
        .clk(clk),
        .rst(rst),
        .anode(anode),
        .seg_out(seg_out),
        .dp(dp),
        .display_value(display_value)
    );

    assign uart_data = display_value[7:0];
    // END DISPLAY CODE
endmodule
