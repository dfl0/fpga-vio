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
    input wire miso,   // JA4 -> SDO

    // sseg
    output wire [3:0] anode,
    output wire [6:0] seg_out,
    output wire dp
);

    // IMU HOOKUP
    wire [15:0] accel_x,
                accel_y,
                accel_z,
                gyro_x,
                gyro_y,
                gyro_z;
    wire imu_done;
    icm20948_controller imu (
        .clk(clk),
        .rst(rst),
        .accel_x(accel_x),
        .accel_y(accel_y),
        .accel_z(accel_z),
        .gyro_x(gyro_x),
        .gyro_y(gyro_y),
        .gyro_z(gyro_z),
        .valid(imu_done),
        .init_error(init_error),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );
    
    // UART HOOKUP
    localparam [15:0] MAGIC_HEADER = 16'hABCD;
    localparam integer FRAME_SIZE = 112;
    reg [FRAME_SIZE-1:0] cur_frame;
    reg uart_start;
    wire uart_ready;
    uart_controller #(.BAUD_RATE(2_000_000)) uart(
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .frame(cur_frame),
        .start(uart_start),
        .ready(uart_ready)
    );

    /// FRAME UPDATE LOGIC
    always @(posedge clk) begin
        uart_start <= 0;
        // constantly send current frame
        if (uart_ready) begin
            uart_start <= 1;
        end
        if (imu_done) begin
            cur_frame <= {
                MAGIC_HEADER,
                accel_x,
                accel_y,
                accel_z,
                gyro_x,
                gyro_y,
                gyro_z
            };
        end
    end

    /// SSEG DISPLAY CODE
    reg [15:0] display_value;
    sseg display (
        .clk(clk),
        .rst(rst),
        .anode(anode),
        .seg_out(seg_out),
        .dp(dp),
        .display_value(display_value)
    );

    // Normal Freq Implementation
    // always @(*) begin
    //     display_value = accel_x;
    // end

    // Lower Freq Implementation
    reg [20:0] delay;
    always @(posedge clk) begin
        if (rst) begin
            delay <= 1;
        end else begin
            if (delay == 0) begin
                display_value <= accel_x;
            end else begin
                delay <= delay + 1;
            end
        end
    end

endmodule
