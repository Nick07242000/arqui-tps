module top #(
    parameter DATA_WIDTH = 8,
    parameter OP_WIDTH   = 6
)(
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] sw,
    input  wire [3:0]            btn,
    output wire [DATA_WIDTH-1:0] led,
    output wire [3:0]            led_aux
);

    // INPUT SIGNALS (ACTIVE LOW)

    wire [DATA_WIDTH-1:0] sw_active_high = ~sw;
    
    wire rst   = ~btn[3]; // Global Reset
    wire en_a  = ~btn[0]; // Enable for Register A
    wire en_b  = ~btn[1]; // Enable for Register B
    wire en_op = ~btn[2]; // Enable for Register OP

    // INTERNAL WIRES (INTERCONNECTS)

    wire [DATA_WIDTH-1:0] val_a;
    wire [DATA_WIDTH-1:0] val_b;
    wire [OP_WIDTH-1:0]   val_op;

    wire [DATA_WIDTH-1:0] alu_result;
    wire                  alu_zero;
    wire                  alu_carry;
    wire                  alu_overflow;

    // MODULE INSTANTIATIONS

    // register A
    register #(
        .WIDTH(DATA_WIDTH)
    ) reg_a_inst (
        .clk(clk),
        .rst(rst),
        .en(en_a),
        .d(sw_active_high),
        .q(val_a)
    );

    // register B
    register #(
        .WIDTH(DATA_WIDTH)
    ) reg_b_inst (
        .clk(clk),
        .rst(rst),
        .en(en_b),
        .d(sw_active_high),
        .q(val_b)
    );

    // register OP
    register #(
        .WIDTH(OP_WIDTH)
    ) reg_op_inst (
        .clk(clk),
        .rst(rst),
        .en(en_op),
        .d(sw_active_high[OP_WIDTH-1:0]),
        .q(val_op)
    );

    // ALU
    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) alu_inst (
        .a(val_a),
        .b(val_b),
        .alu_op(val_op),
        .result(alu_result),
        .zero(alu_zero),
        .carry(alu_carry),
        .overflow(alu_overflow)
    );

    // OUTPUT SIGNALS

    assign led = alu_result;
    assign led_aux = {1'b0, alu_overflow, alu_zero, alu_carry};

endmodule
