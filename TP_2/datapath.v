module datapath #(
    parameter integer DATA_WIDTH = 8,
    parameter integer OP_WIDTH   = 6
)(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // Manual controls
    input  wire [DATA_WIDTH-1:0] i_switch_data,
    input  wire                  i_enable_a_manual,
    input  wire                  i_enable_b_manual,
    input  wire                  i_enable_op_manual,

    // UART/controller controls
    input  wire [DATA_WIDTH-1:0] i_uart_data,
    input  wire                  i_enable_a,
    input  wire                  i_enable_b,
    input  wire                  i_enable_op,

    // Stored values
    output wire [DATA_WIDTH-1:0] o_a,
    output wire [DATA_WIDTH-1:0] o_b,
    output wire [OP_WIDTH-1:0]   o_op,

    // ALU outputs
    output wire [DATA_WIDTH-1:0] o_result,
    output wire                  o_zero,
    output wire                  o_carry,
    output wire                  o_overflow
);

    // Select data and enable source for each register.
    wire [DATA_WIDTH-1:0] reg_a_data =
        i_enable_a_manual ? i_switch_data : i_uart_data;

    wire [DATA_WIDTH-1:0] reg_b_data =
        i_enable_b_manual ? i_switch_data : i_uart_data;

    wire [OP_WIDTH-1:0] reg_op_data =
        i_enable_op_manual
            ? i_switch_data[OP_WIDTH-1:0]
            : i_uart_data[OP_WIDTH-1:0];

    wire reg_a_enable  = i_enable_a_manual  || i_enable_a;
    wire reg_b_enable  = i_enable_b_manual  || i_enable_b;
    wire reg_op_enable = i_enable_op_manual || i_enable_op;

    // Registers
    register #(
        .WIDTH(DATA_WIDTH)
    ) reg_a_inst (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_enable (reg_a_enable),
        .i_data   (reg_a_data),
        .o_data   (o_a)
    );

    register #(
        .WIDTH(DATA_WIDTH)
    ) reg_b_inst (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_enable (reg_b_enable),
        .i_data   (reg_b_data),
        .o_data   (o_b)
    );

    register #(
        .WIDTH(OP_WIDTH)
    ) reg_op_inst (
        .i_clk    (i_clk),
        .i_reset  (i_reset),
        .i_enable (reg_op_enable),
        .i_data   (reg_op_data),
        .o_data   (o_op)
    );

    // ALU
    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) alu_inst (
        .i_a        (o_a),
        .i_b        (o_b),
        .i_alu_op   (o_op),
        .o_result   (o_result),
        .o_zero     (o_zero),
        .o_carry     (o_carry),
        .o_overflow  (o_overflow)
    );

endmodule