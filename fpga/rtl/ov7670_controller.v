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
    parameter integer HEIGHT = 120
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
    output reg ready, // 1 clk pulse when a full frame is stored
    output reg [WIDTH*HEIGHT*16-1:0] image // 16 bits per pixel, row by row
);

    // TODO: add actual sccb controller
    assign sio_c = 1'b1; // idle bus
    assign sio_d = 1'bz; // released (pulled up)

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

    // VIDEO CAPTURE
    localparam IDLE    = 1'b0,
               CAPTURE = 1'b1;
    reg current_state;
    integer cur_row, cur_col, byte_addr;
    always @(*) byte_addr = cur_row*WIDTH*16 + (cur_col ^ 1)*8;

    always @(posedge clk) begin
        // set ready to 0 every cycle
        ready <= 0;
        if (rst) begin
            current_state <= IDLE;
            cur_row <= 0;
            cur_col <= 0;
        end else begin
            case (current_state)
                // only in this state to align image frames
                IDLE: begin
                    if (vsync_rise) begin
                        current_state <= CAPTURE;
                        cur_row <= 0;
                        cur_col <= 0;
                    end
                end
                CAPTURE: begin
                    // if we got a new frame
                    if (vsync_rise) begin
                        ready <= 1;
                        cur_row <= 0;
                        cur_col <= 0;
                    end
                    // if we received a new byte for current row
                    if (byte_valid) begin
                        image[byte_addr +: 8] <= d;
                        cur_col <= cur_col + 1;
                    end
                    // done reading current row
                    if (href_fall) begin
                        cur_row <= cur_row + 1;
                        cur_col <= 0;
                    end
                end
                default: current_state <= IDLE;
            endcase
        end
    end
endmodule
