module blinky #(
    parameter BIT_FAST = 22,
    parameter BIT_SLOW = 23
)(
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
            ledState <= counter[BIT_FAST];
        else
            ledState <= counter[BIT_SLOW];
    end

endmodule
