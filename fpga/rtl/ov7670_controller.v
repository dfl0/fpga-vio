`timescale 1ns/1ps

/*
NOTES: 
- For now, you have to change this module to match the video format you are receiving
- XCLK range for OV7670 is 10-48 Mhz
    - Higher FREQ is faster but harder for FPGA to keep track (since pclk is so fast)
    - 25 Mhz gives 30fps for VGA and QQVGA so thats a good target
- SCCB upper bound for freq is 400Khz
- Since the camera signals are different clock, we have to synchronize them
- Output reg "ready" signals if image is ready to read

TODO:
- might be useful to add an error state for debugging
    - implement index-out-of-bounds for cur_row and cur_col
- include a valid/start wire
    - make this wire reset the camera and over
- instead of integer for address/index, use actual widths for memory efficiency
*/

module ov7670_controller #(
    parameter integer XCLK_FREQ = 24_000_000,
    parameter integer SCCB_FREQ = 200_000,
    parameter integer WIDTH = 160,
    parameter integer HEIGHT = 120,

    // NOTE: TEMPORARY CROP (set to middle 16x16 of QQVGA for now)
    parameter integer CROP_W = 8,
    parameter integer CROP_H = 8

)(
    input wire clk,
    input wire rst,

    // sccb protocol
    output wire sio_c,
    inout wire sio_d,

    // video peripherals
    output reg xclk, // ov7670 system clk input
    input wire pclk, // pixel clock
    input wire href, // horizontal timing
    input wire vsync, // vertical timing
    input wire [7:0] d,

    // module interface
    output reg frame_ready, // 1 clk pulse when a full frame is stored

    // NOTE: TEMPORARY CROP
    // output reg [WIDTH*HEIGHT*16-1:0] image // 16 bits per pixel, row by row
    output reg [CROP_W*CROP_H*16-1:0] image
);

    // HOOKUP OV7670 INITIALIZER
    wire init_done;
    ov7670_init #(.SCCB_FREQ(SCCB_FREQ)) init (
        .clk(clk),
        .rst(rst),
        .sio_c(sio_c),
        .sio_d(sio_d),
        .done(init_done)
    );

    // XCLK
    localparam integer XCLK_HP_CYCLES = 100_000_000 / XCLK_FREQ / 2;
    localparam integer XCLK_DIV_WIDTH = $clog2(XCLK_HP_CYCLES);
    reg [XCLK_DIV_WIDTH:0] xclk_div_ctr;
    always @(posedge clk) begin
        if (rst) begin
            xclk <= 0;
            xclk_div_ctr <= 0;
        end else begin
            if (xclk_div_ctr == XCLK_HP_CYCLES-1) begin
                xclk <= !xclk;
                xclk_div_ctr <= 0;
            end else begin
                xclk_div_ctr <= xclk_div_ctr + 1;
            end
        end
    end

    // SYNCHRONIZATION + EVENTS
    (* ASYNC_REG = "TRUE" *) reg [1:0] pclk_s;
    reg pclk_prev, href_prev, vsync_prev;
    wire pclk_rise = pclk_s[1] && !pclk_prev;
    always @(posedge clk) begin
        if (rst) begin
            pclk_s <= 2'b0;
            pclk_prev <= 1'b0;
            href_prev <= 1'b0;
            vsync_prev <= 1'b0;
        end else begin
            pclk_prev <= pclk_s[1]; // update prev val
            pclk_s <= {pclk_s[0], pclk}; // synchronize
            // sample raw signals
            if (pclk_rise) begin
                href_prev <= href;
                vsync_prev <= vsync;
            end
        end
    end
    wire byte_valid = pclk_rise &&  href;
    wire href_fall  = pclk_rise && !href  &&  href_prev;
    wire vsync_rise = pclk_rise &&  vsync && !vsync_prev;

    // VIDEO CAPTURE LOGI
    localparam STARTUP  = 1'b0,
               CAPTURE  = 1'b1;
    reg current_state;
    integer cur_row, cur_col, byte_addr;
    // switch back to this
    // always @(*) byte_addr = cur_row*WIDTH*16 + (cur_col ^ 1)*8;
    
    // NOTE: TEMPORARY CROP CHANGES
    integer crop_x, crop_y;
    localparam integer CROP_X_MAX = WIDTH - CROP_W - 1;
    localparam integer CROP_Y_MAX = HEIGHT - CROP_H - 1;
    always @(*) byte_addr = (cur_row - crop_y)*CROP_W*16 + ((cur_col - 2*crop_x) ^ 1)*8;
    wire in_crop = (cur_row >= crop_y) && (cur_row < crop_y + CROP_H) &&
                   (cur_col >= 2*crop_x) && (cur_col < 2*(crop_x + CROP_W));

    always @(posedge clk) begin
        if (rst) begin
            current_state <= STARTUP;
            // DEBUG: added crops for now
            crop_x <= 0;
            crop_y <= 0;
        end else begin
            case (current_state)
                STARTUP: begin
                    if (init_done && vsync_rise) begin
                        current_state <= CAPTURE;
                        cur_row <= 0;
                        cur_col <= 0;
                    end
                end
                CAPTURE: begin
                    // one frame fully processed
                    if (vsync_rise) begin
                        frame_ready <= 1;
                        cur_row <= 0;
                        cur_col <= 0;
                        frame_ready <= 1;
                        // DEBUG: update the crop counter as well
                        if (crop_x == CROP_X_MAX) crop_x <= 0;
                        else crop_x <= crop_x + 1;
                        if (crop_y == CROP_Y_MAX) crop_y <= 0;
                        else crop_y <= crop_y + 1;
                    end else begin
                        // frame not ready yet
                        frame_ready <= 0;
                    end

                    // if we received a new byte for current row
                    if (byte_valid) begin
                        cur_col <= cur_col + 1;
                        // image[byte_addr +: 8] <= d;
                        // DEBUG: TEMPORARY CROP UUPDATE 
                        if (in_crop) image[byte_addr +: 8] <= d;
                    end
                    // done reading current row
                    if (href_fall) begin
                        cur_row <= cur_row + 1;
                        cur_col <= 0;
                    end
                end
                // NOTE: this wont actually rerun startup sequence, that only happens on reset
                default: begin
                    current_state <= STARTUP;
                end
            endcase
        end
    end
endmodule
