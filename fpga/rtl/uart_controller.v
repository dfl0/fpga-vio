`timescale 1ns/1ps

/*
NOTES
- "start" signals module to send current frame
- "ready" signals if module able to send next frame
- Takes in frame and sends it fully before sending next one
    - Make sure FRAME_SIZE is divisible by 8
*/

module uart_controller #(
    parameter integer BAUD_RATE = 115_200,
    parameter integer FRAME_SIZE = 112
)(
    // hardware pins
    input wire clk,
    input wire rst,
    output wire tx,

    // logic pins
    input wire [FRAME_SIZE-1:0] frame,

    // module interface
    input wire start,
    output wire ready

);       
    // TRANSMITTER
    reg [7:0] current_packet;
    reg tx_start;
    wire tx_valid;
    wire tx_ready;
    uart_transmitter #(
        .BAUD_RATE(BAUD_RATE)
    ) transmitter (
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .start(tx_start),
        .valid(tx_valid),
        .ready(tx_ready),
        .data(current_packet)
    );

    // STATE MACHINE
    localparam [1:0] IDLE        = 2'b00,
                     LOAD_PACKET = 2'b01,
                     SEND_PACKET = 2'b10,
                     WAIT_PACKET = 2'b11; 
    reg [1:0] current_state;     
    assign ready = current_state == IDLE;

    localparam integer PACKET_COUNT = FRAME_SIZE / 8;
    localparam integer PCK_CNT_WIDTH = $clog2(PACKET_COUNT);
    reg [FRAME_SIZE-1:0] loaded_frame;
    reg [PCK_CNT_WIDTH:0] packet_ctr;

    always @(posedge clk) begin
        if (rst) begin
            tx_start <= 0;
            current_state <= IDLE;
        end else begin
            case (current_state)
                IDLE: begin
                    // check if time to start
                    if (start) begin
                        loaded_frame <= frame;
                        packet_ctr <= 0;
                        current_state <= LOAD_PACKET;
                    end
                end
                LOAD_PACKET: begin
                    // check if we finished
                    if (packet_ctr == PACKET_COUNT) begin
                        current_state <= IDLE;
                    // else load the next packet
                    end else begin
                        // load MSB
                        current_packet <= loaded_frame[FRAME_SIZE-1 -: 8];
                        loaded_frame <= { loaded_frame[FRAME_SIZE-9:0], 8'd0 };
                        packet_ctr <= packet_ctr + 1;
                        current_state <= SEND_PACKET;
                    end
                end
                SEND_PACKET: begin
                    // wait until transmitter is ready
                    if (tx_ready == 1) begin
                        tx_start <= 1;
                        current_state <= WAIT_PACKET;
                    end
                end
                WAIT_PACKET: begin
                    tx_start <= 0;
                    // go to when data is valid/sent
                    if (tx_valid == 1) begin
                        current_state <= LOAD_PACKET;
                    end
                end
                // should never reach here
                default: begin
                    current_state <= IDLE;
                end
            endcase
        end
    end
endmodule
