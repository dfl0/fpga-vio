module icm20948_controller #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer CLK_DIV = 50
)(
    input wire clk,
    input wire rst,

    output reg [7:0] accel_y_h,
    output reg valid,
    output reg init_error,

    // SPI pins driven by the internal SPI master
    output wire cs_n,
    output wire sck,
    output wire mosi,
    input wire miso
);

    // internal spi controls
    reg spi_start;
    reg spi_last;
    reg [7:0] spi_tx_byte;
    wire [7:0] spi_rx_byte;
    wire spi_done;

    spi_master #(.CLK_DIV(CLK_DIV)) spi (
        .clk(clk),
        .rst(rst),
        .start(spi_start),
        .last(spi_last),
        .tx_byte(spi_tx_byte),
        .rx_byte(spi_rx_byte),
        .busy(),
        .done(spi_done),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );

    // all registers used here are in user bank 0
    localparam [6:0] USER_CTRL_ADDR    = 7'h03,
                     WHO_AM_I_ADDR     = 7'h00,
                     PWR_MGMT_1_ADDR   = 7'h06,
                     ACCEL_YOUT_H_ADDR = 7'h2F;
    localparam [7:0] SPI_ONLY     = 8'h10,
                     WAKE         = 8'h01,
                     EXPECTED_ID  = 8'hEA;

    // cycles -> ms based on default 100MHz clock
    localparam integer POWERUP_CYCLES = CLK_HZ / 10; // allow up to 100 ms after powerup before register access
    localparam integer ACCEL_SETTLE_CYCLES = (CLK_HZ / 1000) * 30; // allow 30 ms after wake for the accelerometer (20 ms typical in datasheet)
    reg [31:0] wait_count;

    localparam [4:0] POWERUP_WAIT     = 5'd0,
                     CFG_ISSUE_ADDR  = 5'd1,
                     CFG_WAIT_ADDR   = 5'd2,
                     CFG_ISSUE_DATA  = 5'd3,
                     CFG_WAIT_DATA   = 5'd4,
                     ID_ISSUE_ADDR   = 5'd5,
                     ID_WAIT_ADDR    = 5'd6,
                     ID_ISSUE_DATA   = 5'd7,
                     ID_WAIT_DATA    = 5'd8,
                     WAKE_ISSUE_ADDR = 5'd9,
                     WAKE_WAIT_ADDR  = 5'd10,
                     WAKE_ISSUE_DATA = 5'd11,
                     WAKE_WAIT_DATA  = 5'd12,
                     ACCEL_SETTLE    = 5'd13,
                     POLL_ISSUE_ADDR = 5'd14,
                     POLL_WAIT_ADDR  = 5'd15,
                     POLL_ISSUE_DATA = 5'd16,
                     POLL_WAIT_DATA  = 5'd17,
                     ERROR           = 5'd18;

    reg [4:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= POWERUP_WAIT;
            wait_count <= 32'd0;
            accel_y_h <= 8'd0;
            valid <= 1'b0;
            init_error <= 1'b0;
            spi_start <= 1'b0;
            spi_last <= 1'b0;
            spi_tx_byte <= 8'd0;
        end else begin
            spi_start <= 1'b0;
            valid <= 1'b0;

            case (state)
                POWERUP_WAIT: begin
                    if (wait_count == POWERUP_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        state <= CFG_ISSUE_ADDR;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                // write USER_CTRL = SPI_ONLY: disable the I2C interface
                CFG_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b0, USER_CTRL_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= CFG_WAIT_ADDR;
                end

                CFG_WAIT_ADDR: begin
                    if (spi_done)
                        state <= CFG_ISSUE_DATA;
                end

                CFG_ISSUE_DATA: begin
                    spi_tx_byte <= SPI_ONLY;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= CFG_WAIT_DATA;
                end

                CFG_WAIT_DATA: begin
                    if (spi_done)
                        state <= ID_ISSUE_ADDR;
                end

                // read WHO_AM_I and check that it matches expected
                ID_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b1, WHO_AM_I_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= ID_WAIT_ADDR;
                end

                ID_WAIT_ADDR: begin
                    if (spi_done)
                        state <= ID_ISSUE_DATA;
                end

                ID_ISSUE_DATA: begin
                    spi_tx_byte <= 8'd0;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= ID_WAIT_DATA;
                end

                ID_WAIT_DATA: begin
                    if (spi_done) begin
                        if (spi_rx_byte == EXPECTED_ID) begin
                            state <= WAKE_ISSUE_ADDR;
                        end else begin
                            init_error <= 1'b1;
                            state <= ERROR;
                        end
                    end
                end

                // write PWR_MGMT_1 = WAKE: clear the sleep bit and wake IMU
                WAKE_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b0, PWR_MGMT_1_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= WAKE_WAIT_ADDR;
                end

                WAKE_WAIT_ADDR: begin
                    if (spi_done)
                        state <= WAKE_ISSUE_DATA;
                end

                WAKE_ISSUE_DATA: begin
                    spi_tx_byte <= WAKE;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= WAKE_WAIT_DATA;
                end

                WAKE_WAIT_DATA: begin
                    if (spi_done) begin
                        wait_count <= 32'd0;
                        state <= ACCEL_SETTLE;
                    end
                end

                ACCEL_SETTLE: begin
                    if (wait_count == ACCEL_SETTLE_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        state <= POLL_ISSUE_ADDR;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                // read ACCEL_YOUT_H repeatedly after initializing
                POLL_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b1, ACCEL_YOUT_H_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= POLL_WAIT_ADDR;
                end

                POLL_WAIT_ADDR: begin
                    if (spi_done)
                        state <= POLL_ISSUE_DATA;
                end

                POLL_ISSUE_DATA: begin
                    spi_tx_byte <= 8'd0;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= POLL_WAIT_DATA;
                end

                POLL_WAIT_DATA: begin
                    if (spi_done) begin
                        accel_y_h <= spi_rx_byte;
                        valid <= 1'b1;
                        state <= POLL_ISSUE_ADDR;
                    end
                end

                ERROR: begin
                    // stop polling after a failed identity check until reset
                end

                default: begin
                    state <= ERROR;
                    init_error <= 1'b1;
                    spi_last <= 1'b0;
                end
            endcase
        end
    end

endmodule
