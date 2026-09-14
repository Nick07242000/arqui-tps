module top #(
    parameter DATA_WIDTH = 8,
    parameter OP_WIDTH   = 6
)(
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] sw,
    input  wire [3:0]            btn,
    output wire [DATA_WIDTH-1:0] led,
    output wire [3:0]            led_aux,
    
    // UART physical pins
    input  wire                  uart_rx,
    output wire                  uart_tx
);

    // INPUT SIGNALS (ACTIVE LOW)
    
    wire [DATA_WIDTH-1:0] sw_active_high = ~sw;
    
    wire rst   = ~btn[3]; // button 4: clear registers and reset FSM
    wire en_a  = ~btn[0]; // button 1: load switches to register A
    wire en_b  = ~btn[1]; // button 2: load switches to register B
    wire en_op = ~btn[2]; // button 3: load switches to register OP

    // INTERNAL WIRES

    wire [DATA_WIDTH-1:0] val_a;
    wire [DATA_WIDTH-1:0] val_b;
    wire [OP_WIDTH-1:0]   val_op;

    wire [DATA_WIDTH-1:0] alu_result;
    wire                  alu_zero;
    wire                  alu_carry;
    wire                  alu_overflow;

    // UART INTERFACE WIRES

    wire [7:0] uart_r_data;
    wire       uart_rx_empty;
    wire       uart_tx_full;
    
    wire       fsm_rx_read;
    wire       fsm_en_a;
    wire       fsm_en_b;
    wire       fsm_en_op;
    wire       fsm_tx_start;
    wire [2:0] fsm_tx_sel;

    // UART read trigger is strictly controlled by the FSM
    wire uart_rd_trigger = fsm_rx_read;

    // MULTIPLEXERS (data & enable routing)
    
    // data routing: manual (switches) vs automatic (UART)
    wire [DATA_WIDTH-1:0] reg_a_in  = en_a  ? sw_active_high : uart_r_data;
    wire [DATA_WIDTH-1:0] reg_b_in  = en_b  ? sw_active_high : uart_r_data;
    wire [OP_WIDTH-1:0]   reg_op_in = en_op ? sw_active_high[OP_WIDTH-1:0] : uart_r_data[OP_WIDTH-1:0];

    // enable routing: save if manual button pressed OR if FSM commands it
    wire reg_a_en  = en_a  | fsm_en_a;
    wire reg_b_en  = en_b  | fsm_en_b;
    wire reg_op_en = en_op | fsm_en_op;

    // multipleyer for UART transmission (selects what to send to PC)
    reg [7:0] uart_tx_data_mux;
    always @(*) begin
        case (fsm_tx_sel)
            3'd0: uart_tx_data_mux = val_a;
            3'd1: uart_tx_data_mux = val_b;
            3'd2: uart_tx_data_mux = {2'b00, val_op};
            3'd3: uart_tx_data_mux = alu_result;
            // status byte format: [0000 | TX_FULL | OVERFLOW | ZERO | CARRY]
            3'd4: uart_tx_data_mux = {4'b0000, uart_tx_full, alu_overflow, alu_zero, alu_carry};
            default: uart_tx_data_mux = 8'd0;
        endcase
    end

    // MODULE INSTANTIATIONS
    
    // state machine for the control unit (FSM)
    uart_fsm control_unit (
        .clk(clk),
        .rst(rst),
        .rx_empty(uart_rx_empty),
        .rx_data(uart_r_data), // input to decode command
        .tx_full(uart_tx_full),
        .rx_read(fsm_rx_read),
        .en_a(fsm_en_a),
        .en_b(fsm_en_b),
        .en_op(fsm_en_op),
        .tx_start(fsm_tx_start),
        .tx_sel(fsm_tx_sel)
    );

    uart_top uart_inst (
        .clk(clk),
        .reset(1'b0),
        .rx(uart_rx),
        .tx(uart_tx),
        .rd_uart(uart_rd_trigger),
        .wr_uart(fsm_tx_start),
        .w_data(uart_tx_data_mux), // connected to our multiplexer
        .r_data(uart_r_data),
        .rx_empty(uart_rx_empty),
        .tx_full(uart_tx_full)
    );

    // datapath: registers
    register #(.WIDTH(DATA_WIDTH)) reg_a_inst (
        .clk(clk),
        .rst(rst),
        .en(reg_a_en),
        .d(reg_a_in),
        .q(val_a)
    );

    register #(.WIDTH(DATA_WIDTH)) reg_b_inst (
        .clk(clk),
        .rst(rst),
        .en(reg_b_en),
        .d(reg_b_in),
        .q(val_b)
    );

    register #(.WIDTH(OP_WIDTH)) reg_op_inst (
        .clk(clk),
        .rst(rst),
        .en(reg_op_en),
        .d(reg_op_in),
        .q(val_op)
    );

    // datapath: ALU
    alu #(.DATA_WIDTH(DATA_WIDTH)) alu_inst (
        .a(val_a),
        .b(val_b),
        .alu_op(val_op),
        .result(alu_result),
        .zero(alu_zero),
        .carry(alu_carry),
        .overflow(alu_overflow)
    );

    // PHYSICAL OUTPUTS

    assign led = alu_result;
    assign led_aux = {uart_tx_full, alu_overflow, alu_zero, alu_carry};

endmodule
