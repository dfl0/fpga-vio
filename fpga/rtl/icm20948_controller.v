`timescale 1ns/1ps

module icm20948_controller #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer CLK_DIV = 50
)(
    input wire clk,
    input wire rst,

    output reg signed [15:0] accel_x,
    output reg signed [15:0] accel_y,
    output reg signed [15:0] accel_z,
    output reg signed [15:0] gyro_x,
    output reg signed [15:0] gyro_y,
    output reg signed [15:0] gyro_z,
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
        .done(spi_done),
        .cs_n(cs_n),
        .sck(sck),
        .mosi(mosi),
        .miso(miso)
    );

    localparam [6:0] USER_CTRL_ADDR    = 7'h03,
                     WHO_AM_I_ADDR     = 7'h00,
                     PWR_MGMT_1_ADDR   = 7'h06,
                     INT_STATUS_1_ADDR = 7'h1A,
                     ACCEL_XOUT_H_ADDR = 7'h2D,
                     REG_BANK_SEL_ADDR = 7'h7F;
    localparam [7:0] SPI_ONLY     = 8'h10,
                     WAKE         = 8'h01,
                     EXPECTED_ID  = 8'hEA;

    // cycles -> ms based on default 100MHz clock
    localparam integer POWERUP_CYCLES = CLK_HZ / 10; // allow up to 100 ms after powerup before register access
    localparam integer ACCEL_SETTLE_CYCLES = (CLK_HZ / 1000) * 30; // allow 30 ms after wake for the accelerometer (20 ms typical in datasheet)
    reg [31:0] wait_count;
    reg [3:0] byte_index;
    reg [95:0] sample_shift;
    reg [2:0] config_step;
    reg [6:0] config_addr;
    reg [7:0] config_data;
    reg discard_first_ready;

    // possible states
    localparam [4:0] POWERUP_WAIT    = 5'd0,
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
                     ODR_SETUP        = 5'd14,
                     ODR_ISSUE_ADDR   = 5'd15,
                     ODR_WAIT_ADDR    = 5'd16,
                     ODR_ISSUE_DATA   = 5'd17,
                     ODR_WAIT_DATA    = 5'd18,
                     READY_ISSUE_ADDR = 5'd19,
                     READY_WAIT_ADDR  = 5'd20,
                     READY_ISSUE_DATA = 5'd21,
                     READY_WAIT_DATA  = 5'd22,
                     BURST_ISSUE_ADDR = 5'd23,
                     BURST_WAIT_ADDR  = 5'd24,
                     BURST_ISSUE_BYTE = 5'd25,
                     BURST_WAIT_BYTE  = 5'd26,
                     ERROR            = 5'd27;

    reg [4:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= POWERUP_WAIT;
            wait_count <= 32'd0;
            accel_x <= 16'd0;
            accel_y <= 16'd0;
            accel_z <= 16'd0;
            gyro_x <= 16'd0;
            gyro_y <= 16'd0;
            gyro_z <= 16'd0;
            valid <= 1'b0;
            init_error <= 1'b0;
            spi_start <= 1'b0;
            spi_last <= 1'b0;
            spi_tx_byte <= 8'd0;
            byte_index <= 4'd0;
            sample_shift <= 96'd0;
            config_step <= 3'd0;
            config_addr <= 7'd0;
            config_data <= 8'd0;
            discard_first_ready <= 1'b1;
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
                        config_step <= 3'd0;
                        state <= ODR_SETUP;
                    end
                end

                // bank 2: enable filtered output, align accel/gyro ODR,
                // and configure both dividers for ~102 Hz samples
                ODR_SETUP: begin
                    case (config_step)
                        3'd0: begin config_addr <= REG_BANK_SEL_ADDR; config_data <= 8'h20; end
                        3'd1: begin config_addr <= 7'h01; config_data <= 8'h09; end // GYRO_CONFIG_1: DLPF mode 1
                        3'd2: begin config_addr <= 7'h14; config_data <= 8'h01; end // ACCEL_CONFIG: DLPF enabled
                        3'd3: begin config_addr <= 7'h09; config_data <= 8'h01; end // ODR_ALIGN_EN
                        3'd4: begin config_addr <= 7'h00; config_data <= 8'h0A; end // GYRO_SMPLRT_DIV
                        3'd5: begin config_addr <= 7'h10; config_data <= 8'h00; end // ACCEL_SMPLRT_DIV_1
                        3'd6: begin config_addr <= 7'h11; config_data <= 8'h0A; end // ACCEL_SMPLRT_DIV_2
                        3'd7: begin config_addr <= REG_BANK_SEL_ADDR; config_data <= 8'h00; end
                    endcase
                    state <= ODR_ISSUE_ADDR;
                end

                ODR_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b0, config_addr};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= ODR_WAIT_ADDR;
                end

                ODR_WAIT_ADDR: begin
                    if (spi_done)
                        state <= ODR_ISSUE_DATA;
                end

                ODR_ISSUE_DATA: begin
                    spi_tx_byte <= config_data;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= ODR_WAIT_DATA;
                end

                ODR_WAIT_DATA: begin
                    if (spi_done) begin
                        if (config_step == 3'd7) begin
                            wait_count <= 32'd0;
                            state <= ACCEL_SETTLE;
                        end else begin
                            config_step <= config_step + 1'b1;
                            state <= ODR_SETUP;
                        end
                    end
                end

                ACCEL_SETTLE: begin
                    if (wait_count == ACCEL_SETTLE_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        state <= READY_ISSUE_ADDR;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                // poll data-ready; reading the status register clears the ready flag
                READY_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b1, INT_STATUS_1_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    state <= READY_WAIT_ADDR;
                end

                READY_WAIT_ADDR: begin
                    if (spi_done)
                        state <= READY_ISSUE_DATA;
                end

                READY_ISSUE_DATA: begin
                    spi_tx_byte <= 8'd0;
                    spi_last <= 1'b1;
                    spi_start <= 1'b1;
                    state <= READY_WAIT_DATA;
                end

                READY_WAIT_DATA: begin
                    if (spi_done) begin
                        if (discard_first_ready) begin
                            // clear any status left over from the settling delay
                            discard_first_ready <= 1'b0;
                            state <= READY_ISSUE_ADDR;
                        end else begin
                            state <= spi_rx_byte[0] ? BURST_ISSUE_ADDR : READY_ISSUE_ADDR;
                        end
                    end
                end

                // bank 0 contains six consecutive high/low accel and gyro pairs
                BURST_ISSUE_ADDR: begin
                    spi_tx_byte <= {1'b1, ACCEL_XOUT_H_ADDR};
                    spi_last <= 1'b0;
                    spi_start <= 1'b1;
                    byte_index <= 4'd0;
                    state <= BURST_WAIT_ADDR;
                end

                BURST_WAIT_ADDR: begin
                    if (spi_done)
                        state <= BURST_ISSUE_BYTE;
                end

                BURST_ISSUE_BYTE: begin
                    spi_tx_byte <= 8'd0;
                    spi_last <= (byte_index == 4'd11);
                    spi_start <= 1'b1;
                    state <= BURST_WAIT_BYTE;
                end

                BURST_WAIT_BYTE: begin
                    if (spi_done) begin
                        sample_shift <= {sample_shift[87:0], spi_rx_byte};
                        if (byte_index == 4'd11) begin
                            // include final byte without waiting for the shift register update
                            {accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z}
                                <= {sample_shift[87:0], spi_rx_byte};
                            valid <= 1'b1;
                            state <= READY_ISSUE_ADDR;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            state <= BURST_ISSUE_BYTE;
                        end
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
