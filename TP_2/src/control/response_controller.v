// Response Controller
//
// Controls the sequence of response bytes transmitted by UART.
//
// Response sequence:
//   0 -> Register A
//   1 -> Register B
//   2 -> ALU operation
//   3 -> ALU result
//   4 -> Status
//
// The controller does not know what the response data contains.
// It only controls when to start a transmission and which response
// should be selected.
//
// A one-clock wait state is kept after o_tx_start so the UART has
// time to assert its busy signal, matching the original uart_fsm.

module response_controller #(
    parameter integer RESPONSE_COUNT = 5
)(
    input  wire i_clk,
    input  wire i_reset,

    // Start response sequence
    input  wire i_start,

    // UART transmit status
    input  wire i_tx_busy,

    // UART transmit control
    output reg                  o_tx_start,
    output wire [2:0]           o_tx_index
);

    // =================================================================
    // State definitions
    // =================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_TX_LOAD    = 3'd1;
    localparam STATE_TX_START   = 3'd2;
    localparam STATE_TX_WAIT_1  = 3'd3;
    localparam STATE_TX_WAIT_2  = 3'd4;

    // =================================================================
    // Internal registers
    // =================================================================

    reg [2:0] state;
    reg [2:0] next_state;

    reg [2:0] response_index;
    reg [2:0] next_response_index;

    // =================================================================
    // State register
    // =================================================================

    always @(posedge i_clk) begin
        if (i_reset) begin
            state          <= STATE_IDLE;
            response_index <= 3'd0;
        end
        else begin
            state          <= next_state;
            response_index <= next_response_index;
        end
    end

    // =================================================================
    // Response selector
    // =================================================================

    assign o_tx_index = response_index;

    // =================================================================
    // Next-state and control logic
    // =================================================================

    always @(*) begin

        // Defaults
        next_state          = state;
        next_response_index = response_index;

        o_tx_start = 1'b0;

        case (state)

            // ---------------------------------------------------------
            // Wait for command_controller to finish a transaction
            // ---------------------------------------------------------

            STATE_IDLE: begin
                if (i_start) begin
                    next_response_index = 3'd0;
                    next_state = STATE_TX_LOAD;
                end
            end

            // ---------------------------------------------------------
            // Wait until UART TX is ready
            // ---------------------------------------------------------

            STATE_TX_LOAD: begin
                if (!i_tx_busy)
                    next_state = STATE_TX_START;
            end

            // ---------------------------------------------------------
            // Start current transmission
            // ---------------------------------------------------------

            STATE_TX_START: begin
                o_tx_start = 1'b1;
                next_state = STATE_TX_WAIT_1;
            end

            // ---------------------------------------------------------
            // One-clock delay
            //
            // Gives the UART time to assert tx_busy after tx_start.
            // ---------------------------------------------------------

            STATE_TX_WAIT_1: begin
                next_state = STATE_TX_WAIT_2;
            end

            // ---------------------------------------------------------
            // Wait until current byte has finished transmitting
            // ---------------------------------------------------------

            STATE_TX_WAIT_2: begin
                if (!i_tx_busy) begin

                    if (response_index == RESPONSE_COUNT - 1) begin
                        // All response bytes have been transmitted.
                        next_state = STATE_IDLE;
                    end
                    else begin
                        // Move to the next response.
                        next_response_index = response_index + 1'b1;
                        next_state = STATE_TX_LOAD;
                    end

                end
            end

            default: begin
                next_state = STATE_IDLE;
            end

        endcase
    end

endmodule