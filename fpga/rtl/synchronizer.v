// TODO: this is not necessary for IMU, different sync algo needs to be used
module synchronizer (
    parameter WIDTH = 1;
)(
    input wire clk,
    input wire [WIDTH-1:0] raw_signal,
    output reg [WIDTH-1:0] synced_signal
);

    reg [WIDTH-1:0] stage1_signal;

    always @ (posedge clk) begin
        stage1_signals <= raw_signal;
        synced_signal <= stage1_signals;
    end
endmodule