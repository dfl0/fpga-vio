`timescale 1ns/1ps

/*
NOTES
- Takes in frame and sends it fully before sending next one
    - Right now sends 112 bit frame (14 packets)
    - Frame can be changed multiple times, only latest value
        - NOTE: might need busy to prevent writing during copying

TODO
- Make FRAME_SIZE parameter
    - Also derive packet index and other frame sizes from this
*/

module uart_controller #(
    parameter integer BAUD_RATE = 115_200
)(
    // hardware pins
    input wire clk,
    input wire rst,
    output wire tx,

    // logic pins
    input wire [111:0] frame
);
    // constants
    localparam [1:0] LOAD_FRAME  = 2'b00,
                     LOAD_PACKET = 2'b01,
                     SEND_PACKET = 2'b10,
                     WAIT_PACKET = 2'b11; 
    
    // internal
    reg [1:0] current_state;

    reg [111:0] loaded_frame;
    reg [15:0] packet_idx; // supports max packet count 65535 (524288 bits)
    reg [7:0] current_packet;
    
    reg tx_start;
    wire tx_valid;
    wire tx_ready;
    
    // hook up uart_transmitter
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

    always @(posedge clk) begin
        if (rst) begin
            tx_start <= 0;
            current_state <= LOAD_FRAME;
        end else begin
            case (current_state)
                LOAD_FRAME: begin
                    loaded_frame <= frame;
                    packet_idx <= 0;
                    current_state <= LOAD_PACKET;
                end
                LOAD_PACKET: begin
                    // check if we finished
                    if (packet_idx == 14) begin
                        current_state <= LOAD_FRAME;
                    // else load the next packet
                    end else begin
                        current_packet <= loaded_frame[7:0];
                        // shift loaded_frame for next packet
                        loaded_frame <= {loaded_frame[111:8], 8'h00};
                        packet_idx <= packet_idx + 1;
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
                    current_state <= LOAD_FRAME;
                end
            endcase
        end
    end
endmodule
