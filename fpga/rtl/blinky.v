module blinky(
    input clk10,
    input dip,
    output led
);

    reg [31:0] counter = 0;
    reg ledState = 0;

    assign led = ledState;

    always @ (posedge clk10)
    begin
        counter <= counter + 1;
        if (dip)
            ledState <= counter[22];
        else
            ledState <= counter[23];
    end

endmodule
