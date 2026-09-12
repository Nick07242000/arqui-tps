module register #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst, // active HIGH reset
    input  wire             en,  // active HIGH enable
    input  wire [WIDTH-1:0] d,   // data input
    output reg  [WIDTH-1:0] q    // data output
);

    always @(posedge clk) begin
        if (rst) begin
            q <= {WIDTH{1'b0}};  // clear all bits on reset
        end else if (en) begin
            q <= d;              // load data on enable
        end
    end

endmodule