`timescale 1ns/1ps

/*
NOTES: 
- This modules job is to just initialize the camera
- Does not implicitly start on RST, user has to set start manually
- Interface
    - "start" tells module to start initialization sequence
    - "done" indicates that startup has finished
*/

module ov7670_init #(
    parameter integer SCCB_FREQ = 200_000
)(
    input wire clk,
    input wire rst,

    // sccb protocol interface
    output wire sio_c,
    inout wire sio_d,

    // module interface
    input wire start,
    output reg done
);
    // HOOKUP SCCB WRITER
    reg [7:0] reg_addr, write_data;
    reg writer_valid;
    wire writer_ready;
    sccb_writer #(
        .CLK_FREQ(SCCB_FREQ)
    ) writer (
        .clk(clk),
        .rst(rst),
        .sio_c(sio_c),
        .sio_d(sio_d),
        .reg_addr(reg_addr),
        .write_data(write_data),
        .valid(writer_valid),
        .ready(writer_ready)
    );

    // STATE MACHINE
    localparam [1:0]    IDLE = 2'd0,
                        RESET_CAM = 2'd1,
                        RESET_CAM_WAIT = 2'd2,
                        SET_COLOR_BAR = 2'd3;
    reg [1:0] current_state;

    // helpful constants
    localparam integer CYCLES_10_MILLIS = 1_000_000; // basys 3 cycle count for 10 millis
    reg [$clog2(CYCLES_10_MILLIS)-1:0] timer_ctr;

    always @(posedge clk) begin
        if (rst) begin
            done <= 0;
            writer_valid <= 0;       
            current_state <= IDLE;     
        end else begin
            case (current_state) 
                // wait for start signal (writer should be ready too)
                IDLE: begin
                    // send the reset signal 0x70 = 0xBA
                    if (start && writer_ready) begin
                        done <= 0; // not done anymore
                        reg_addr <= 8'h70;
                        write_data <= 8'hba;
                        writer_valid <= 1;
                        current_state <= RESET_CAM;
                    end
                end
                RESET_CAM: begin
                    // for for finish write
                    if (writer_ready) begin
                        timer_ctr <= 0;
                        current_state <= RESET_CAM_WAIT;
                    end
                end
                RESET_CAM_WAIT: begin
                    // send the color bar signal 0x71 = 0x35 after waiting 10ms
                    if (writer_ready && timer_ctr == CYCLES_10_MILLIS-1) begin
                        // send the color bar signal 0x71 = 0x35
                        reg_addr <= 8'h71;
                        write_data <= 8'h35;
                        current_state <= SET_COLOR_BAR;
                    end else begin
                        timer_ctr <= timer_ctr + 1;
                    end
                end
                SET_COLOR_BAR: begin
                    // mark done when finish
                    if (writer_ready) begin
                        done <= 1;
                        current_state <= IDLE;
                    end
                end
                default: begin
                    done <= 0;
                    writer_valid <= 0;
                    current_state <= IDLE;
                end
            endcase
        end
    end
endmodule
