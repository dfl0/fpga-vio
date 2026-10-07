    // shows value of 16 bit number
    module sseg (
        input clk,
        input reg [15:0] value, 

        output reg [3:0] anode,
        output reg [6:0] seg_out, 
    );
        // keeps track of sseg internal state
        reg [17:0] clk_div_en; // 480Hz clock
        reg [1:0] anode_ctr;
        
        // intermediary wire 
        reg [3:0] cur_digit;

        // combinational logic for each segment
        always (*) begin
            // select the current digit
            case (anode_ctr)
                2'b00: begin
                    cur_digit = value[3:0];
                    anode = 4'b1110;
                end
                2'b01: begin
                    cur_digit = value[7:4];
                    anode = 4'b1101;
                end
                2'b10: begin
                    cur_digit = value[11:8];
                    anode = 4'b1011;
                end
                2'b11: begin
                    cur_digit = value[15:12];
                    anode = 4'b0111;
                end
                default: begin
                    cur_digit = 0;
                    anode = 0;
                end
            endcase

            // set the segments
            case (cur_digit)
                1'h0: seg_out = 1'b0000001;
                1'h1: seg_out = 1'b1001111;
                1'h2: seg_out = 1'b0010010;
                1'h3: seg_out = 1'b0000110;
                1'h4: seg_out = 1'b1001100;
                1'h5: seg_out = 1'b0100100;
                1'h6: seg_out = 1'b0100000;
                1'h7: seg_out = 1'b0001111;
                1'h8: seg_out = 1'b0000000;
                1'h9: seg_out = 1'b0000100;
                1'ha: seg_out = 1'b0000001;
                1'hb: seg_out = 1'b1100000;
                1'hc: seg_out = 1'b0110001;
                1'hd: seg_out = 1'b1000010;
                1'he: seg_out = 1'b0110000;
                1'hf: seg_out = 1'b0111000;
                default: seg_out = 1'b0000000;
            endcase
        end

        // update internal state
        always @(posedge clk) begin
            clk_div_en <= clk_div_en + 1;

            if (clk_div_en == 0 ) begin
                anode_ctr <= anode_ctr + 1;
            end
        end

    endmodule