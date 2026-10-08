`timescale 1ns/1ps

// display 16-bit hex value
module sseg (
    input wire clk,
    input wire rst,
    input wire [15:0] display_value,
    output reg [3:0] anode,
    output reg [6:0] seg_out
);

    // at 100 MHz, advance one digit about 480 times per second (120 scans/s)
    localparam integer CYCLES_PER_DIGIT = 100_000_000 / 480;
    reg [17:0] scan_count;
    reg [1:0] anode_ctr;
    reg [3:0] cur_digit;

    always @(*) begin
        case (anode_ctr)
            2'b00: begin
                cur_digit = display_value[3:0];
                anode = 4'b1110;
            end
            2'b01: begin
                cur_digit = display_value[7:4];
                anode = 4'b1101;
            end
            2'b10: begin
                cur_digit = display_value[11:8];
                anode = 4'b1011;
            end
            2'b11: begin
                cur_digit = display_value[15:12];
                anode = 4'b0111;
            end
            default: begin
                cur_digit = 4'h0;
                anode = 4'b1111;
            end
        endcase

        // seg_out[6:0] drive segments {a,b,c,d,e,f,g}; 0 = lit (active low)
        case (cur_digit)
            4'h0: seg_out = 7'b0000001;
            4'h1: seg_out = 7'b1001111;
            4'h2: seg_out = 7'b0010010;
            4'h3: seg_out = 7'b0000110;
            4'h4: seg_out = 7'b1001100;
            4'h5: seg_out = 7'b0100100;
            4'h6: seg_out = 7'b0100000;
            4'h7: seg_out = 7'b0001111;
            4'h8: seg_out = 7'b0000000;
            4'h9: seg_out = 7'b0000100;
            4'ha: seg_out = 7'b0001000;
            4'hb: seg_out = 7'b1100000;
            4'hc: seg_out = 7'b0110001;
            4'hd: seg_out = 7'b1000010;
            4'he: seg_out = 7'b0110000;
            4'hf: seg_out = 7'b0111000;
            default: seg_out = 7'b1111111;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            scan_count <= 18'd0;
            anode_ctr <= 2'd0;
        end else if (scan_count == CYCLES_PER_DIGIT - 1) begin
            scan_count <= 18'd0;
            anode_ctr <= anode_ctr + 1;
        end else begin
            scan_count <= scan_count + 1'b1;
        end
    end

endmodule
