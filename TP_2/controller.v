module controller (
    input  wire       i_clk,
    input  wire       i_reset,

    // UART receive
    input  wire       i_rx_empty,
    input  wire [7:0] i_rx_data,
    output reg        o_rx_read,

    // Datapath register enables
    output reg        o_enable_a,
    output reg        o_enable_b,
    output reg        o_enable_op,

    // UART transmit
    input  wire       i_tx_full,
    output reg        o_tx_start,

    // Selects the response byte to transmit
    output wire [2:0] o_tx_select
);

    // FSM states
    localparam [3:0]
        STATE_IDLE          = 4'd0,
        STATE_WAIT_CMD_ACK  = 4'd1,
        STATE_WAIT_VALUE    = 4'd2,
        STATE_WAIT_VAL_ACK  = 4'd3,
        STATE_WAIT_TX_READY = 4'd4,
        STATE_START_TX      = 4'd5,
        STATE_TX_DELAY      = 4'd6,
        STATE_WAIT_TX_DONE  = 4'd7;

    reg [3:0] state;
    reg [3:0] next_state;

    // Received command: 0 = A, 1 = B, 2 = OP
    reg [7:0] command;
    reg [7:0] next_command;

    // Response byte: 0 = A, 1 = B, 2 = OP, 3 = result, 4 = status
    reg [2:0] tx_select;
    reg [2:0] next_tx_select;


    // State registers
    always @(posedge i_clk) begin
        if (i_reset) begin
            state     <= STATE_IDLE;
            command   <= 8'd0;
            tx_select <= 3'd0;
        end
        else begin
            state     <= next_state;
            command   <= next_command;
            tx_select <= next_tx_select;
        end
    end

    assign o_tx_select = tx_select;

    // Next-state and output logic
    always @(*) begin
        next_state     = state;
        next_command   = command;
        next_tx_select = tx_select;

        o_rx_read   = 1'b0;
        o_enable_a  = 1'b0;
        o_enable_b  = 1'b0;
        o_enable_op = 1'b0;
        o_tx_start  = 1'b0;

        case (state)

            // Wait for a new command byte.
            STATE_IDLE: begin
                next_tx_select = 3'd0;

                if (!i_rx_empty) begin
                    next_command = i_rx_data;
                    o_rx_read    = 1'b1;
                    next_state   = STATE_WAIT_CMD_ACK;
                end
            end

            // Wait until the command byte has been removed from the RX buffer.
            STATE_WAIT_CMD_ACK: begin
                if (i_rx_empty)
                    next_state = STATE_WAIT_VALUE;
            end

            // Wait for the value associated with the command.
            STATE_WAIT_VALUE: begin
                if (!i_rx_empty) begin

                    case (command)
                        8'd0: o_enable_a  = 1'b1;
                        8'd1: o_enable_b  = 1'b1;
                        8'd2: o_enable_op = 1'b1;
                        default: ;
                    endcase

                    o_rx_read  = 1'b1;
                    next_state = STATE_WAIT_VAL_ACK;
                end
            end

            // Wait until the value byte has been removed from the RX buffer.
            STATE_WAIT_VAL_ACK: begin
                if (i_rx_empty)
                    next_state = STATE_WAIT_TX_READY;
            end

            // Wait until the transmitter is ready for the next response byte.
            STATE_WAIT_TX_READY: begin
                if (!i_tx_full)
                    next_state = STATE_START_TX;
            end

            // Start transmission of the selected response byte.
            STATE_START_TX: begin
                o_tx_start = 1'b1;
                next_state = STATE_TX_DELAY;
            end

            // Give the transmitter one cycle to update its busy status.
            STATE_TX_DELAY: begin
                next_state = STATE_WAIT_TX_DONE;
            end

            // Wait for the current response byte to finish transmitting.
            STATE_WAIT_TX_DONE: begin
                if (!i_tx_full) begin
                    if (tx_select == 3'd4)
                        next_state = STATE_IDLE;
                    else begin
                        next_tx_select = tx_select + 1'b1;
                        next_state     = STATE_WAIT_TX_READY;
                    end
                end
            end

            default: begin
                next_state = STATE_IDLE;
            end

        endcase
    end

endmodule
