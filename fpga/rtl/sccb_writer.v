`timescale 1ns/1ps

/*
NOTES: 
- This module only sends 3-phase-writes to the sccb controller
    - For our project this is all we need
*/

module sccb_writer #(
    parameter integer CLK_FREQ = 200_000
)(
    input wire clk,
    input wire rst,

    // sccb protocol interface
    output reg sio_c,
    inout wire sio_d,

    // data required for 3-phase write cycle
    input wire [7:0] reg_addr,
    input wire [7:0] write_data,
    
    // module interface
    input wire valid,
    output wire ready
);

    // CLOCK LOGIC
    localparam integer CYCLES_FULL_PERIOD =  100_000_000 / CLK_FREQ;
    localparam integer CYCLES_HALF_PERIOD =  CYCLES_FULL_PERIOD / 2;
    localparam integer CYCLES_QUARTER_PERIOD =  CYCLES_HALF_PERIOD / 2;
    localparam integer CYCLES_THREE_QUARTER =  CYCLES_HALF_PERIOD + CYCLES_QUARTER_PERIOD;
    localparam integer CLK_DIV_WIDTH = $clog2(CYCLES_FULL_PERIOD);
    reg [CLK_DIV_WIDTH:0] clk_div_ctr;
    
    wire full_period = clk_div_ctr == CYCLES_FULL_PERIOD-1;
    wire half_period = clk_div_ctr == CYCLES_HALF_PERIOD-1; // we write to sio_d here
    wire quarter_period = clk_div_ctr == CYCLES_QUARTER_PERIOD-1; // we toggle sio_c low here
    wire three_quarters = clk_div_ctr == CYCLES_THREE_QUARTER-1;  // we toggle sio_c high here

    always @(posedge clk) begin 
        if (rst) begin
            clk_div_ctr <= 0;
        end else begin
            // reset clk
            if (full_period || ready) begin
                clk_div_ctr <= 0;
            end else begin
                clk_div_ctr <= clk_div_ctr + 1;
            end
        end
    end

    // STATE LOGIC
    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     WRITE = 2'd2,
                     STOP  = 2'd3;
    reg [1:0] current_state;
    reg [4:0] internal_ctr;
    reg [26:0] sccb_data; // 3 phases x 9 bits per phase
    assign ready = current_state == IDLE;

    // control sio_d based on internal wire (release line on high and pull down when low)
    reg internal_sio_d;
    assign sio_d = internal_sio_d ? 1'bz : 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            // setup idle state
            current_state <= IDLE;
            sio_c <= 1;
            internal_sio_d <= 1;
        end else begin
            case (current_state)
                // wait for valid signal
                IDLE: begin
                    if (valid) begin
                        // load data (slave_addr, ACK, reg_addr, ACK, write_data, ACK)
                        sccb_data <= { 8'h42, 1'b1, reg_addr, 1'b1, write_data, 1'b1 };
                        // initiate start sequence (set sio_d low)
                        internal_sio_d <= 0;
                        current_state <= START;
                    end
                end
                // hold sio_d=0 sio_c=1 for at least quarter period before setting sio_c=0
                START: begin
                    if (quarter_period) begin
                        // reset clock again
                        sio_c <= 0;
                        // setup write state
                        current_state <= WRITE;
                        internal_ctr <= 0;
                    end
                end
                // send all data
                WRITE: begin
                    if (quarter_period) begin
                        sio_c <= 0;
                    end
                    if (three_quarters) begin
                        sio_c <= 1;
                    end
                    // in the middle of sio_c low, write data
                    if (half_period) begin
                        // start STOP seq after last bit has been clocked
                        if (internal_ctr == 5'd27) begin
                            internal_sio_d <= 0;
                            current_state <= STOP;
                        end else begin
                            internal_sio_d <= sccb_data[26-internal_ctr]; // MSB first
                            internal_ctr <= internal_ctr + 1;
                        end             
                    end
                end
                // NOTE: we enter this state starting from a half period
                STOP: begin
                    // hold sio_d=0, sio_c=0 for a quarter period
                    if (three_quarters) begin
                        sio_c <= 1;
                    end
                    // hold sio_d=0, sio_c=1 for another quarter period
                    if (full_period) begin
                        internal_sio_d <= 1;
                    end
                    // wait a half period before allowing another transaction to start
                    if (half_period) begin
                        current_state <= IDLE;
                    end
                end
                // should never reach here
                default: begin
                    current_state <= IDLE;
                    sio_c <= 1;
                    internal_sio_d <= 1;
                end
            endcase
        end
    end
endmodule
