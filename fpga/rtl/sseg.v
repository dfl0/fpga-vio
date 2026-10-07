    // shows value of 16 bit number
    module sseg (
        input clk,
        input wire [15:0] display_value, 

        output reg [3:0] anode,
        output reg [6:0] seg_out
    );
        // keeps track of sseg internal state
        reg [17:0] clk_div_en; // 480Hz clock
        reg [1:0] anode_ctr;
        
        // intermediary wire 
        reg [3:0] cur_digit;

        // combinational logic for each segment
        always @(*) begin
            // select the current digit
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
                    cur_digit = 0;
                    anode = 0;
                end
            endcase

            // set the segments
            case (cur_digit)
                4'h0: seg_out = 7'b1000000;
                4'h1: seg_out = 7'b1001111;
                4'h2: seg_out = 7'b0010010;
                4'h3: seg_out = 7'b0000110;
                4'h4: seg_out = 7'b1001100;
                4'h5: seg_out = 7'b0100100;
                4'h6: seg_out = 7'b0100000;
                4'h7: seg_out = 7'b0001111;
                4'h8: seg_out = 7'b0000000;
                4'h9: seg_out = 7'b0000100;
                4'ha: seg_out = 7'b0000001;
                4'hb: seg_out = 7'b1100000;
                4'hc: seg_out = 7'b0110001;
                4'hd: seg_out = 7'b1000010;
                4'he: seg_out = 7'b0110000;
                4'hf: seg_out = 7'b0111000;
                default: seg_out = 7'b0000000;
            endcase
        end

        // update internal state
        always @(posedge clk) begin
            clk_div_en <= clk_div_en + 1;

            if (clk_div_en == 18'b0 ) begin
                anode_ctr <= anode_ctr + 1;
            end
        end

    endmodule