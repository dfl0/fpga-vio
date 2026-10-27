`timescale 1ns/1ps

/*
NOTES:
- Supports max 12Mbaud (limited by Basys3's onboard FTH2332 chip)
    - No check included, up to module user
- Only set data when ready is 1
- Wait until ready is 1 again to send next byted
    - There might be issue where could immeaditly put next data in same cycle?
    - There is a start input
- Hardcoded constants:
    - 8 bits of data
    - 10 bits transmitted per packet
*/

module uart_transmitter #(
    parameter integer BAUD_RATE = 115_200
)(
    // hardware pins
    input wire clk,
    input wire rst,
    output reg tx,

    // logic pins
    output reg valid,
    output reg ready,
    input wire start,
    input wire [7:0] data
);
    // constants
    localparam [1:0] READY    = 2'b00,
                     LOAD     = 2'b01,
                     TRANSMIT = 2'b10; 
    localparam integer CLK_HZ = 100_000_000;
    localparam integer BAUD_FREQ = CLK_HZ / BAUD_RATE;

    // internal
    reg [31:0] baud_counter;
    reg [3:0] data_index;
    reg [9:0] uart_packet;
    reg [1:0] current_state;

    // procedural
    always @(posedge clk) begin
        if (rst) begin
            ready <= 0;
            tx <= 1;
            valid <= 0;
            current_state <= READY;
        end else begin
            case (current_state)
                READY: begin
                    // can recieve a new packet now
                    ready <= 1;
                    // tx set default to 1 in uart
                    tx <= 1;
                    if (start == 1) begin
                        current_state <= LOAD;
                    end
                end
                LOAD: begin
                    // lock receiving
                    ready <= 0;
                    valid <= 0;
                    // prepare the uart packet
                    uart_packet[8:1] <= data;
                    uart_packet[0] <= 0; // start bit always 0
                    uart_packet[9] <= 1; // stop bit always 1
                    // get ready to transmit
                    data_index <= 0;
                    baud_counter <= 0;
                    current_state <= TRANSMIT;
                end
                TRANSMIT: begin
                    // transmit using BAUD_RATE frequency
                    if (baud_counter == (BAUD_FREQ - 1)) begin
                        tx <= uart_packet[data_index];
                        data_index <= data_index + 1;
                        baud_counter <= 0;
                        // if this was the last byte
                        if (data_index == 9) begin
                            valid <= 1;
                            current_state <= READY;
                        end
                    // wait until next BAUD_RATE cycle
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                // should theoretically never reach here
                default: begin
                    current_state <= READY;
                end
            endcase
        end 
    end

endmodule