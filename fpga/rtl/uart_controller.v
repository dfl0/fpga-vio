`timescale 1ns/1ps

/*
NOTES
- What should be the datatypes (wire/reg) that drives the data for transmitter and this controller module?
- How can I guarentee that tx_start wont be 1 when tx_valid is set?

TODO:
- Right now will only send the latest updated value for tx_byte
    - Add a FIFO/buffer to not miss any data
    - If serialization added, then change data from reg to wire
*/
module uart_controller #(
    parameter integer BAUD_RATE = 115_200
)(
    // hardware pins
    input wire clk,
    input wire rst,
    output wire tx,

    // logic pins
    // NOTE: wire for now
    input wire [7:0] data // wire for now
);
    // constants
    localparam [1:0] SEND = 2'b00,
                     WAIT = 2'b01,
                     READ = 2'b10;
    
    // internal
    reg [1:0] current_state;
    reg tx_start;

    // outputs
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
        .data(data)
    );


    // procedural
    always @(posedge clk) begin
        if (rst) begin
            current_state <= SEND;
            tx_start <= 0;
        end else begin
            case (current_state)
                SEND: begin
                    // wait until transmitter is ready
                    if (tx_ready == 1) begin
                        tx_start <= 1;
                        current_state <= WAIT;
                    end
                end
                WAIT: begin
                    tx_start <= 0;
                    // go to when data is valid/sent
                    if (tx_valid == 1) begin
                        current_state <= SEND;
                    end
                end
                // shoudl never reach here
                default: begin
                    current_state <= SEND;
                end
            endcase
        end
    end


endmodule