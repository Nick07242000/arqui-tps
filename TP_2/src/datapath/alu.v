// Arithmetic Logic Unit (ALU)

module alu #(
    parameter integer DATA_WIDTH = 8
)(
    input  wire [DATA_WIDTH-1:0] i_a,
    input  wire [DATA_WIDTH-1:0] i_b,
    input  wire [5:0]            i_alu_op,

    output reg  [DATA_WIDTH-1:0] o_result,
    output wire                  o_zero,
    output reg                   o_carry,
    output reg                   o_overflow
);

    //============================================================
    // ALU operation codes
    //============================================================
    localparam OP_ADD = 6'b100000;
    localparam OP_SUB = 6'b100010;
    localparam OP_AND = 6'b100100;
    localparam OP_OR  = 6'b100101;
    localparam OP_XOR = 6'b100110;
    localparam OP_NOR = 6'b100111;
    localparam OP_SRL = 6'b000010;
    localparam OP_SRA = 6'b000011;

    // Number of bits needed to represent a shift amount.
    localparam SHIFT_WIDTH =
        (DATA_WIDTH <= 2) ? 1 : $clog2(DATA_WIDTH);

    //============================================================
    // Internal ALU result
    //============================================================
    // One extra bit is kept so that arithmetic operations can
    // provide the carry output.
    reg [DATA_WIDTH:0] ext_result;

    //============================================================
    // ALU operation logic
    //============================================================
    always @(*) begin

        // Default values prevent unintended latches.
        ext_result = 0;
        o_overflow = 0;

        case (i_alu_op)

            //----------------------------------------------------
            // Addition
            //----------------------------------------------------
            OP_ADD: begin
                ext_result = i_a + i_b;

                // Signed overflow occurs when two operands with
                // the same sign produce a result with a different sign.
                o_overflow =
                    (i_a[DATA_WIDTH-1] == i_b[DATA_WIDTH-1]) &&
                    (ext_result[DATA_WIDTH-1] != i_a[DATA_WIDTH-1]);
            end

            //----------------------------------------------------
            // Subtraction
            //----------------------------------------------------
            OP_SUB: begin
                ext_result = i_a - i_b;

                // Signed overflow occurs when operands with
                // different signs produce an unexpected result sign.
                o_overflow =
                    (i_a[DATA_WIDTH-1] != i_b[DATA_WIDTH-1]) &&
                    (ext_result[DATA_WIDTH-1] != i_a[DATA_WIDTH-1]);
            end

            //----------------------------------------------------
            // Logical operations
            //----------------------------------------------------
            OP_AND:
                ext_result = {1'b0, i_a & i_b};

            OP_OR:
                ext_result = {1'b0, i_a | i_b};

            OP_XOR:
                ext_result = {1'b0, i_a ^ i_b};

            OP_NOR:
                ext_result = {1'b0, ~(i_a | i_b)};

            //----------------------------------------------------
            // Shift operations
            //----------------------------------------------------
            OP_SRL:
                ext_result = {1'b0, i_a >> i_b[SHIFT_WIDTH-1:0]};

            OP_SRA:
                ext_result = {1'b0, $signed(i_a) >>> i_b[SHIFT_WIDTH-1:0]};

            //----------------------------------------------------
            // Unsupported operation
            //----------------------------------------------------
            default: ; // Keep default values.
        endcase

        // The lower DATA_WIDTH bits are the actual ALU result.
        o_result = ext_result[DATA_WIDTH-1:0];

        // The extra bit contains the carry from arithmetic operations.
        o_carry = ext_result[DATA_WIDTH];
    end

    // High when the ALU result is zero.
    assign o_zero = (o_result == 0);

endmodule
