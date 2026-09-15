// Response Multiplexer
//
// Converts the response index into the byte that should be sent
// through the UART.
//
// Response index:
//   0 -> Register A
//   1 -> Register B
//   2 -> ALU operation
//   3 -> ALU result
//   4 -> Status
//
// Status format: [0000 | TX_BUSY | OVERFLOW | ZERO | CARRY]

module response_mux #(
    parameter integer DATA_WIDTH = 8,
    parameter integer OP_WIDTH   = 6
)(
    input  wire [2:0]            i_index,

    // Datapath values
    input  wire [DATA_WIDTH-1:0] i_a,
    input  wire [DATA_WIDTH-1:0] i_b,
    input  wire [OP_WIDTH-1:0]   i_op,
    input  wire [DATA_WIDTH-1:0] i_result,

    // Status information
    input  wire                  i_tx_busy,
    input  wire                  i_overflow,
    input  wire                  i_zero,
    input  wire                  i_carry,

    output reg [DATA_WIDTH-1:0]  o_data
);

    // =================================================================
    // Response selection
    // =================================================================

    always @(*) begin

        case (i_index)

            // Register A
            3'd0:
                o_data = i_a;

            // Register B
            3'd1:
                o_data = i_b;

            // ALU operation
            3'd2:
                o_data = {{(DATA_WIDTH-OP_WIDTH){1'b0}}, i_op};

            // ALU result
            3'd3:
                o_data = i_result;

            // Status
            3'd4:
                o_data = {
                    4'b0000,
                    i_tx_busy,
                    i_overflow,
                    i_zero,
                    i_carry
                };

            default:
                o_data = {DATA_WIDTH{1'b0}};

        endcase
    end

endmodule