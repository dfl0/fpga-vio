`timescale 1ns/1ps

module spi_master_tb;

    reg tb_clk;
    reg tb_rst;

    reg        tb_start;
    reg        tb_last;
    reg  [7:0] tb_tx_byte;
    wire [7:0] tb_rx_byte;
    wire       tb_busy;
    wire       tb_done;

    wire tb_cs_n;
    wire tb_sck;
    wire tb_mosi;
    reg  tb_miso;

    spi_master #(.CLK_DIV(5)) dut (
        .clk(tb_clk),
        .rst(tb_rst),

        .start(tb_start),
        .last(tb_last),
        .tx_byte(tb_tx_byte),
        .rx_byte(tb_rx_byte),
        .busy(tb_busy),
        .done(tb_done),

        .cs_n(tb_cs_n),
        .sck(tb_sck),
        .mosi(tb_mosi),
        .miso(tb_miso)
    );

    initial tb_clk = 0;
    // 5ns half-period => 10ns total clock period, matching Basys 3 100MHz clock
    always begin
        #5;
        tb_clk = ~tb_clk;
    end

    reg [7:0] expected_rx;
    reg [7:0] expected_tx;

    integer rx_bit_idx;
    integer tx_bit_idx;

    // check MOSI on each SPI clock rising edge
    always @(posedge tb_sck) begin
        if (!tb_cs_n) begin
            if (tx_bit_idx < 8) begin
                if (tb_mosi !== expected_tx[7 - tx_bit_idx]) begin
                    $display("ERROR: MOSI mismatch at bit %0d", tx_bit_idx);
                    $display("Expected: %b, Got: %b",
                             expected_tx[7 - tx_bit_idx], tb_mosi);
                    $fatal;
                end
            end

            tx_bit_idx = tx_bit_idx + 1;
        end
    end

    // simulate peripheral changing MISO on falling edges
    always @(negedge tb_sck) begin
        if (!tb_cs_n && rx_bit_idx < 7) begin
            rx_bit_idx = rx_bit_idx + 1;
            tb_miso = expected_rx[7 - rx_bit_idx];
        end
    end

    // perform one byte transfer
    task transfer_byte;
        input [7:0] tx;
        input [7:0] rx;
        input       is_last;

        begin
            expected_tx = tx;
            expected_rx = rx;

            tx_bit_idx = 0;
            rx_bit_idx = 0;

            // simulate the peripheral already driving first bit on MISO before the first SPI clock rising edge
            tb_miso = rx[7];

            // set transfer inputs while SPI master is idle
            @(negedge tb_clk);
            tb_tx_byte = tx;
            tb_last = is_last;
            tb_start = 1'b1;

            @(negedge tb_clk);
            tb_start = 1'b0;

            // wait for completion with timeout
            fork
                begin
                    wait(tb_done == 1'b1);
                end

                begin
                    repeat (1000) @(posedge tb_clk);
                    $display("ERROR: Transfer timeout");
                    $fatal;
                end
            join_any
            disable fork;

            // Allow nonblocking assignments to settle.
            #1;

            if (tb_rx_byte !== rx) begin
                $display("ERROR: RX mismatch");
                $display("Expected: %h, Got: %h", rx, tb_rx_byte);
                $fatal;
            end

            if (tx_bit_idx != 8) begin
                $display("ERROR: Expected 8 transmitted bits, got %0d",
                         tx_bit_idx);
                $fatal;
            end

            if (tb_busy !== 1'b0) begin
                $display("ERROR: busy should be low after completion");
                $fatal;
            end

            if (is_last && tb_cs_n !== 1'b1) begin
                $display("ERROR: CS should be high after final byte");
                $fatal;
            end

            if (!is_last && tb_cs_n !== 1'b0) begin
                $display("ERROR: CS should remain low between bytes");
                $fatal;
            end

            $display("PASS: TX=%h RX=%h last=%b",
                     tx, rx, is_last);
        end
    endtask

    // main test sequence
    initial begin
        $dumpfile("sim/spi_master.vcd");
        $dumpvars(0, spi_master_tb.dut);

        tb_rst = 1'b1;
        tb_start = 1'b0;
        tb_last = 1'b0;
        tb_tx_byte = 8'h00;
        tb_miso = 1'b0;

        expected_tx = 8'h00;
        expected_rx = 8'h00;

        tx_bit_idx = 0;
        rx_bit_idx = 0;

        // hold reset for several clock cycles (simulating button click)
        repeat (5) @(negedge tb_clk);
        tb_rst = 1'b0;

        // allow the DUT to leave reset
        repeat (2) @(negedge tb_clk);

        if (tb_cs_n !== 1'b1 || tb_busy !== 1'b0 || tb_sck !== 1'b0) begin
            $display("ERROR: Incorrect reset/idle state");
            $fatal;
        end

        $display("Starting SPI tests...");

        // first byte: CS must remain asserted
        transfer_byte(8'hA5, 8'h3C, 1'b0);

        // second byte: CS must be deasserted at completion
        transfer_byte(8'h96, 8'hD2, 1'b1);

        $display("All SPI tests passed.");

        repeat (10) @(posedge tb_clk);

        $finish;
    end

endmodule
