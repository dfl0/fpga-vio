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
    output wire done
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
    localparam [2:0]    RESET_CAM = 3'd0,
                        RESET_CAM_WAIT = 3'd1,
                        WAIT_10_MS = 3'd2,
                        SET_COLOR_BAR = 3'd3,
                        SET_COLOR_BAR_WAIT = 3'd4,
                        DONE = 3'd5;
    reg [2:0] current_state;
    assign done = current_state == DONE; // done output tied reaching done state

    // 10 millis timer vars
    localparam integer CYCLES_10_MILLIS = 1_000_000; // basys 3 cycle count for 10 millis
    reg [$clog2(CYCLES_10_MILLIS)-1:0] timer_ctr;

    always @(posedge clk) begin
        if (rst) begin
            current_state <= RESET_CAM;     
        end else begin
            case (current_state) 
                RESET_CAM: begin
                    if (writer_ready) begin
                        reg_addr <= 8'h70;
                        write_data <= 8'hba;
                        writer_valid <= 1;
                        current_state <= RESET_CAM_WAIT;
                    end
                end
                RESET_CAM_WAIT: begin
                    writer_valid <= 0;
                    if (writer_ready) begin
                        timer_ctr <= 0;
                        current_state <= WAIT_10_MS;
                    end
                end
                WAIT_10_MS: begin
                    if (timer_ctr == CYCLES_10_MILLIS-1) begin
                        current_state <= SET_COLOR_BAR;
                    end else begin
                        timer_ctr <= timer_ctr + 1;
                    end
                end
                SET_COLOR_BAR: begin
                    if (writer_ready) begin
                        reg_addr <= 8'h71;
                        write_data <= 8'h35;
                        writer_valid <= 1;
                        current_state <= SET_COLOR_BAR_WAIT;
                    end else begin
                        timer_ctr <= timer_ctr + 1;
                    end
                end
                SET_COLOR_BAR_WAIT: begin
                    writer_valid <= 0;
                    if (writer_ready) begin
                        current_state <= DONE;
                    end
                end
                default: begin
                    current_state <= RESET_CAM;
                end
            endcase
        end
    end
endmodule
