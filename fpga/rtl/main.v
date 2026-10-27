`timescale 1ns/1ps

module main (
    input wire clk,

    // debug
    input wire rst, // v17
    output reg sample_seen, // u16
    output wire init_error, // e19
    
    // uart
    output wire tx,

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

    wire signed [15:0] accel_x;
    wire sample_valid;

        // latch controller's one clock wide valid signal to see it on the LED
    always @(posedge clk) begin
        if (rst)
            sample_seen <= 1'b0;
        else if (sample_valid)
            sample_seen <= 1'b1;
    end

    // NORMAL
    // wire [15:0] display_value;
    // assign display_value = accel_x;
    // assign dp = 1'b1; // active-low decimal point, off

    // DEBUG DISPLAY AT LOWER FREQ
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

    icm20948_controller imu (
        .clk(clk),
        .rst(rst),
        .accel_x(accel_x),
        .accel_y(),
        .accel_z(),
        .gyro_x(),
        .gyro_y(),
        .gyro_z(),
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

    
    // DEBUG: for now just output the MSB of accel_x
    wire [7:0] uart_data;
    assign uart_data = display_value[7:0];
    uart_controller uart(
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .data(uart_data)
    );


endmodule
