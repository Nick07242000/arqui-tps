module alu #(
    parameter DATA_WIDTH = 8
)(
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [5:0]            alu_op,
    output reg  [DATA_WIDTH-1:0] result,
    output wire                  zero,
    output reg                   carry,
    output reg                   overflow
);

    localparam OP_ADD = 6'b100000;
    localparam OP_SUB = 6'b100010;
    localparam OP_AND = 6'b100100;
    localparam OP_OR  = 6'b100101;
    localparam OP_XOR = 6'b100110;
    localparam OP_NOR = 6'b100111;
    localparam OP_SRL = 6'b000010;
    localparam OP_SRA = 6'b000011;

    localparam SHIFT_WIDTH = (DATA_WIDTH <= 2) ? 1 : $clog2(DATA_WIDTH);

    reg [DATA_WIDTH:0] ext_result;

    always @(*) begin
        ext_result = {(DATA_WIDTH+1){1'b0}};
        overflow   = 1'b0;

        case (alu_op)
            OP_ADD: begin
                ext_result = a + b;
                overflow = (a[DATA_WIDTH-1] == b[DATA_WIDTH-1]) && (ext_result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
            end
            
            OP_SUB: begin
                ext_result = a - b;
                overflow = (a[DATA_WIDTH-1] != b[DATA_WIDTH-1]) && (ext_result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
            end
            
            OP_AND:  ext_result = {1'b0, a & b};
            OP_OR:   ext_result = {1'b0, a | b};
            OP_XOR:  ext_result = {1'b0, a ^ b};
            OP_NOR:  ext_result = {1'b0, ~(a | b)};
            OP_SRL:  ext_result = {1'b0, a >> b[SHIFT_WIDTH-1:0]};
            OP_SRA:  ext_result = {1'b0, $signed(a) >>> b[SHIFT_WIDTH-1:0]};
            
            default: ext_result = {(DATA_WIDTH+1){1'b0}};
        endcase

        result = ext_result[DATA_WIDTH-1:0];
        carry  = ext_result[DATA_WIDTH];
    end

    assign zero = (result == {DATA_WIDTH{1'b0}}) ? 1'b1 : 1'b0;

endmodule
