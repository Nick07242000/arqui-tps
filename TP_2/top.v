module top #(
    parameter integer DATA_WIDTH = 8,
    parameter integer OP_WIDTH   = 6
)(
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] sw,
    input  wire [3:0]            btn,

    output wire [DATA_WIDTH-1:0] led,
    output wire [3:0]            led_aux,

    input  wire                  uart_rx,
    output wire                  uart_tx
);

    // INPUT SIGNALS (ACTIVE LOW)
    wire [DATA_WIDTH-1:0] switch_data = ~sw;

    wire reset                        = ~btn[3];
    wire enable_a_manual              = ~btn[0];
    wire enable_b_manual              = ~btn[1];
    wire enable_op_manual             = ~btn[2];

    // UART SIGNALS
    wire [DATA_WIDTH-1:0] uart_rx_data;
    wire [DATA_WIDTH-1:0] uart_tx_data;

    wire uart_rx_empty;
    wire uart_tx_full;

    wire uart_rx_read;
    wire uart_tx_start;

    // CONTROLLER SIGNALS
    wire controller_enable_a;
    wire controller_enable_b;
    wire controller_enable_op;

    wire [2:0] tx_select;

    // DATAPATH SIGNALS
    wire [DATA_WIDTH-1:0] datapath_a;
    wire [DATA_WIDTH-1:0] datapath_b;
    wire [OP_WIDTH-1:0]   datapath_op;

    wire [DATA_WIDTH-1:0] alu_result;
    wire alu_zero;
    wire alu_carry;
    wire alu_overflow;

    
    // ========================================================
    // POWER ON RESET
    // 16-cycle active-high power-on reset generator
    // ========================================================
    reg [3:0] por_shift = 4'b0;
    wire por_reset = !por_shift[3];
    
    always @(posedge clk) begin
        por_shift <= {por_shift[2:0], 1'b1};
    end
    
    wire system_reset = reset || por_reset;


    // ========================================================
    // UART RESPONSE DATA MUX
    // The controller tells us which byte to transmit.
    // ========================================================
    reg [DATA_WIDTH-1:0] uart_tx_data_mux;

    always @(*) begin
        case (tx_select)
            3'd0: uart_tx_data_mux = datapath_a;
            3'd1: uart_tx_data_mux = datapath_b;
            3'd2: uart_tx_data_mux = {2'b00, datapath_op};
            3'd3: uart_tx_data_mux = alu_result;
            // status byte format: [0000 | TX_FULL | OVERFLOW | ZERO | CARRY]
            3'd4: uart_tx_data_mux = {4'b0000, uart_tx_full, alu_overflow, alu_zero, alu_carry};
            default: uart_tx_data_mux = 8'd0;
        endcase
    end

    assign uart_tx_data = uart_tx_data_mux;


    // ========================================================
    // CONTROLLER
    // ========================================================
    controller controller_inst (
        .i_clk        (clk),
        .i_           (system_reset),

        .i_rx_empty   (uart_rx_empty),
        .i_rx_data    (uart_rx_data),
        .o_rx_read    (uart_rx_read),

        .o_enable_a   (controller_enable_a),
        .o_enable_b   (controller_enable_b),
        .o_enable_op  (controller_enable_op),

        .i_tx_full    (uart_tx_full),
        .o_tx_start   (uart_tx_start),

        .o_tx_select  (tx_select)
    );


    // ========================================================
    // UART INTERFACE
    // ========================================================

    uart_interface #(
        .CLK_FREQ        (27_000_000),
        .BAUD_RATE       (9_600),
        .DATA_BITS       (DATA_WIDTH),
        .OVERSAMPLE_RATE (16)
    ) uart_interface_inst (
        .i_clk        (clk),
        .i_reset      (system_reset),
        .i_rx         (uart_rx),
        .i_rd_uart    (uart_rx_read),
        .i_wr_uart    (uart_tx_start),
        .i_write_data (uart_tx_data),
        .o_tx         (uart_tx),
        .o_rx_empty   (uart_rx_empty),
        .o_tx_busy    (uart_tx_full),
        .o_read_data  (uart_rx_data)
    );


    // ========================================================
    // DATAPATH
    // ========================================================

    datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH  (OP_WIDTH)
    ) datapath_inst (
        .i_clk   (clk),
        .i_reset (system_reset),

        // Manual inputs
        .i_switch_data       (switch_data),
        .i_enable_a_manual   (enable_a_manual),
        .i_enable_b_manual   (enable_b_manual),
        .i_enable_op_manual  (enable_op_manual),

        // UART data
        .i_uart_data (uart_rx_data),

        // Controller register enables
        .i_enable_a  (controller_enable_a),
        .i_enable_b  (controller_enable_b),
        .i_enable_op (controller_enable_op),

        // Register outputs
        .o_a  (datapath_a),
        .o_b  (datapath_b),
        .o_op (datapath_op),

        // ALU outputs
        .o_result   (alu_result),
        .o_zero     (alu_zero),
        .o_carry    (alu_carry),
        .o_overflow (alu_overflow)
    );


    // ========================================================
    // PHYSICAL OUTPUTS
    // ========================================================

    // Main LEDs show ALU result.
    assign led = alu_result;

    // Auxiliary LEDs show ALU/UART status.
    assign led_aux = {
        uart_tx_full,
        alu_overflow,
        alu_zero,
        alu_carry
    };

endmodule
