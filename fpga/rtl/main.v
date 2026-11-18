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
    output wire dp,

    // camera1
    output wire sio_c,
    inout wire sio_d,
    output wire xclk,
    input wire pclk,
    input wire href,
    input wire vsync,
    input wire [7:0] d
);
    // CAMERA HOOKUP
    localparam integer CROP_W = 8;
    localparam integer CROP_H = 8;
    wire camera1_ready;
    wire [CROP_W*CROP_H*16-1:0] camera1_image;

    ov7670_controller #(
        .XCLK_FREQ(10_000_000),
        .CROP_W(CROP_W),
        .CROP_H(CROP_H)
    ) camera1 (
        .clk(clk),
        .rst(rst),
        .sio_c(sio_c),
        .sio_d(sio_d),
        .xclk(xclk),
        .pclk(pclk),
        .href(href),
        .vsync(vsync),
        .d(d),
        .ready(camera1_ready),
        .image(camera1_image)
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
    localparam integer IMAGE_BITS = CROP_W * CROP_H * 16;
    localparam integer FRAME_SIZE = 16 + 64 + 96 + IMAGE_BITS;
    reg [6:0] us_div;
    reg [63:0] time_us, imu_time_us;
    reg [95:0] imu_data;
    reg [IMAGE_BITS-1:0] latest_image;
    reg imu_pending;
    wire uart_ready;
    wire uart_start = imu_pending && uart_ready;
    uart_controller #(
        .BAUD_RATE(2_000_000),
        .FRAME_SIZE(FRAME_SIZE)
    ) uart(
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .frame({MAGIC_HEADER, imu_time_us, imu_data, latest_image}),
        .start(uart_start),
        .ready(uart_ready)
    );

    always @(posedge clk) begin
        if (rst) begin
            us_div <= 0;
            time_us <= 0;
            imu_pending <= 0;
            latest_image <= 0;
        end else begin
            if (us_div == 99) begin
                us_div <= 0;
                time_us <= time_us + 1'b1;
            end else begin
                us_div <= us_div + 1'b1;
            end
            if (camera1_ready)
                latest_image <= camera1_image;
            if (uart_start)
                imu_pending <= 0;
            if (imu_done) begin
                imu_time_us <= time_us;
                imu_data <= {accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z};
                imu_pending <= 1;
            end
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
