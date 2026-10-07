module spi_master #(
    parameter integer CLK_DIV = 50
)(
    input wire clk,
    input wire rst,

    // controller interface
    input wire start,
    input wire last,
    input wire [7:0] tx_byte,
    output reg [7:0] rx_byte,
    output reg busy,
    output reg done,

    // SPI pins      physical pin labels on Adafruit ICM-20948
    output reg cs_n, // CS
    output reg sck,  // SCL
    output reg mosi, // SDA
    input wire miso  // SDO
);
    // internal state
    localparam integer DIV_WIDTH = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    reg [DIV_WIDTH-1:0] clk_div_cnt;
    reg [2:0] bit_count;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    always @(posedge clk) begin
        if (rst) begin
            // Reset everything
            clk_div_cnt <= 0;
            bit_count <= 0;
            tx_shift <= 8'h00;
            rx_shift <= 8'h00;

            rx_byte <= 8'h00;
            busy <= 1'b0;
            done <= 1'b0;

            cs_n <= 1'b1;
            sck <= 1'b0;
            mosi <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                // set idle SPI state
                sck <= 1'b0;
                clk_div_cnt <= 0;

                if (start) begin // signal received to start communication
                    // set up initial state of SPI communication
                    // (happens before first rising edge on sck)
                    busy <= 1'b1;
                    cs_n <= 1'b0;

                    bit_count <= 0;
                    tx_shift <= tx_byte;
                    rx_shift <= 8'h00;

                    mosi <= tx_byte[7];
                end
            end else begin
                // active transaction, generate SPI clock signal
                if (clk_div_cnt == CLK_DIV - 1) begin // half-period reached
                    clk_div_cnt <= 1'b0;

                    if (!sck) begin // rising (leading) edge
                        // drive SPI clock high and read first bit on miso
                        sck <= 1'b1;
                        rx_shift <= {rx_shift[6:0], miso}; // shift into LSB
                    end else begin  // falling (trailing) edge
                        // drive SPI clock low and start sending next bit on mosi
                        sck <= 1'b0;

                        if (bit_count == 3'd7) begin
                            // last bit of current byte
                            done <= 1'b1;
                            busy <= 1'b0;
                            rx_byte <= rx_shift; // receive last bit

                            if (last) begin // last byte of stream
                                cs_n <= 1'b1;
                                mosi <= 1'b0;
                            end else begin
                                mosi <= 1'b0;
                            end
                        end else begin
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            mosi <= tx_shift[6];
                            bit_count <= bit_count + 1'b1;
                        end
                    end
                end else begin // wait another clk half-period
                    clk_div_cnt <= clk_div_cnt + 1'b1;
                end
            end
        end
    end

endmodule
