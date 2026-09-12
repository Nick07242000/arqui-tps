module baud_rate_generator #(
    parameter CLOCK_FREQ = 27000000,
    parameter BAUD_RATE  = 9600
)(
    input  wire clk,
    input  wire reset,
    output wire tick
);
    localparam MOD = CLOCK_FREQ / (BAUD_RATE * 16);
    
    reg [10:0] r_reg;
    wire [10:0] r_next;

    always @(posedge clk) begin
        if (reset)
            r_reg <= 0;
        else
            r_reg <= r_next;
    end

    assign r_next = (r_reg == (MOD - 1)) ? 0 : r_reg + 1;
    assign tick = (r_reg == (MOD - 1)) ? 1'b1 : 1'b0;

endmodule
