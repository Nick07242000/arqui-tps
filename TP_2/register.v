module register #(
    parameter integer WIDTH = 8
)(
    input  wire             i_clk,
    input  wire             i_reset,
    input  wire             i_enable,
    input  wire [WIDTH-1:0] i_data,

    output reg  [WIDTH-1:0] o_data
);

    always @(posedge i_clk) begin

        // Reset has priority over the enable signal.
        if (i_reset) begin
            o_data <= {WIDTH{1'b0}};
        end

        // Load new data when the register is enabled.
        else if (i_enable) begin
            o_data <= i_data;
        end
    end

endmodule