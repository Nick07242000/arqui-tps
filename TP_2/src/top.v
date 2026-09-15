// Top Module
//
// Integrates the communication, control, and computation blocks.
// The top module is responsible only for connecting these blocks
// together and handling the physical FPGA inputs/outputs.

module top #(
    parameter integer DATA_WIDTH = 8,
    parameter integer OP_WIDTH   = 6
)(
    input  wire                  clk,

    // Physical inputs
    input  wire [DATA_WIDTH-1:0] sw,
    input  wire [3:0]            btn,

    // Physical outputs
    output wire [DATA_WIDTH-1:0] led,
    output wire [3:0]            led_aux,

    // UART physical pins
    input  wire                  uart_rx,
    output wire                  uart_tx
);

    // =================================================================
    // INPUT SIGNALS
    // =================================================================
    //
    // Switches and buttons are active-low on the board.

    wire [DATA_WIDTH-1:0] switch_data = ~sw;

    wire reset = ~btn[3];

    wire enable_a_manual  = ~btn[0];
    wire enable_b_manual  = ~btn[1];
    wire enable_op_manual = ~btn[2];


    // =================================================================
    // UART INTERFACE SIGNALS
    // =================================================================

    wire [DATA_WIDTH-1:0] uart_rx_data;
    wire                  uart_rx_empty;
    wire                  uart_tx_full;

    wire                  uart_rx_read;
    wire                  uart_tx_start;

    wire [DATA_WIDTH-1:0] uart_tx_data;


    // =================================================================
    // COMMAND CONTROLLER SIGNALS
    // =================================================================

    wire [DATA_WIDTH-1:0] command_value;

    wire command_enable_a;
    wire command_enable_b;
    wire command_enable_op;

    wire command_done;


    // =================================================================
    // RESPONSE CONTROLLER SIGNALS
    // =================================================================

    wire [2:0] response_index;


    // =================================================================
    // DATAPATH SIGNALS
    // =================================================================

    wire [DATA_WIDTH-1:0] datapath_a;
    wire [DATA_WIDTH-1:0] datapath_b;
    wire [OP_WIDTH-1:0]   datapath_op;

    wire [DATA_WIDTH-1:0] alu_result;
    wire                  alu_zero;
    wire                  alu_carry;
    wire                  alu_overflow;


    // =================================================================
    // COMMAND CONTROLLER
    // =================================================================
    // It controls the datapath register enables and tells the
    // response controller when the complete command is finished.

    command_controller #(
        .DATA_WIDTH(DATA_WIDTH)
    )
    command_controller_inst (
        .i_clk          (clk),
        .i_reset        (reset),

        .i_rx_empty     (uart_rx_empty),
        .i_rx_data      (uart_rx_data),

        .o_rx_read      (uart_rx_read),
        .o_value        (command_value),

        .o_enable_a     (command_enable_a),
        .o_enable_b     (command_enable_b),
        .o_enable_op    (command_enable_op),

        .o_command_done (command_done)
    );


    // =================================================================
    // RESPONSE CONTROLLER
    // =================================================================
    // Once command_done is asserted, send:
    // A -> B -> OP -> RESULT -> STATUS

    response_controller #(
        .RESPONSE_COUNT(5)
    )
    response_controller_inst (
        .i_clk          (clk),
        .i_reset        (reset),

        .i_start        (command_done),
        .i_tx_busy      (uart_tx_full),

        .o_tx_start     (uart_tx_start),
        .o_tx_index     (response_index)
    );


    // =================================================================
    // RESPONSE MULTIPLEXER
    // =================================================================
    // Converts the response index into the actual byte to transmit.

    response_mux #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH  (OP_WIDTH)
    )
    response_mux_inst (
        .i_index      (response_index),

        .i_a          (datapath_a),
        .i_b          (datapath_b),
        .i_op         (datapath_op),
        .i_result     (alu_result),

        .i_tx_busy    (uart_tx_full),
        .i_overflow   (alu_overflow),
        .i_zero       (alu_zero),
        .i_carry      (alu_carry),

        .o_data       (uart_tx_data)
    );


    // =================================================================
    // DATAPATH
    // =================================================================
    // Contains the A, B and OP registers and the ALU.
    // The UART value comes from command_controller rather than directly
    // from uart_interface. This guarantees that the value used for
    // the register load is the byte captured before rx_read consumes it.

    datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH  (OP_WIDTH)
    )
    datapath_inst (
        .i_clk                (clk),
        .i_reset              (reset),

        .i_switch_data        (switch_data),

        .i_enable_a_manual    (enable_a_manual),
        .i_enable_b_manual    (enable_b_manual),
        .i_enable_op_manual   (enable_op_manual),

        .i_uart_data          (command_value),

        .i_enable_a           (command_enable_a),
        .i_enable_b           (command_enable_b),
        .i_enable_op          (command_enable_op),

        .o_a                  (datapath_a),
        .o_b                  (datapath_b),
        .o_op                 (datapath_op),

        .o_result             (alu_result),
        .o_zero               (alu_zero),
        .o_carry              (alu_carry),
        .o_overflow           (alu_overflow)
    );


    // =================================================================
    // UART INTERFACE
    // =================================================================
    // Connects the byte-level system interface to the UART RX/TX
    // modules and baud-rate generator.

    uart_interface #(
        .CLK_FREQ        (27_000_000),
        .BAUD_RATE       (9_600),
        .DATA_BITS       (DATA_WIDTH),
        .OVERSAMPLE_RATE (16)
    )
    uart_interface_inst (
        .i_clk        (clk),
        .i_reset      (reset),

        .i_rx         (uart_rx),
        .i_rd_uart    (uart_rx_read),

        .i_wr_uart    (uart_tx_start),
        .i_write_data (uart_tx_data),

        .o_tx         (uart_tx),

        .o_read_data  (uart_rx_data),
        .o_rx_empty   (uart_rx_empty),
        .o_tx_full    (uart_tx_full)
    );


    // =================================================================
    // PHYSICAL OUTPUTS
    // =================================================================

    // Display ALU result on main LEDs.
    assign led = alu_result;

    // Auxiliary LEDs:
    // [TX_BUSY | OVERFLOW | ZERO | CARRY]
    assign led_aux = {
        uart_tx_full,
        alu_overflow,
        alu_zero,
        alu_carry
    };

endmodule