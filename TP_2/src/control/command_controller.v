// Command Controller
//
// Handles the incoming UART command/value sequence.
//
// Expected format:
//   [COMMAND][VALUE]
//
// Commands:
//   0 -> Load register A
//   1 -> Load register B
//   2 -> Load ALU operation
//
// The controller:
//   1. Receives the command byte.
//   2. Waits for the command byte to be consumed.
//   3. Receives and stores the value byte.
//   4. Loads the selected register.
//   5. Waits for the value byte to be consumed.
//   6. Generates command_done to start the response sequence.
//
// This preserves the important timing behavior of the original
// uart_fsm while separating command handling from TX handling.

module command_controller #(
    parameter integer DATA_WIDTH = 8
)(
    input  wire                  i_clk,
    input  wire                  i_reset,

    // UART receive interface
    input  wire                  i_rx_empty,
    input  wire [DATA_WIDTH-1:0] i_rx_data,

    // UART read control
    output reg                   o_rx_read,

    // Value captured from UART
    output reg [DATA_WIDTH-1:0]  o_value,

    // Datapath register enables
    output reg                   o_enable_a,
    output reg                   o_enable_b,
    output reg                   o_enable_op,

    // Indicates that the complete command/value transaction is done
    output reg                   o_command_done
);

    // =================================================================
    // State definitions
    // =================================================================

    localparam STATE_IDLE      = 3'd0;
    localparam STATE_CMD_ACK   = 3'd1;
    localparam STATE_WAIT_DATA = 3'd2;
    localparam STATE_LOAD      = 3'd3;
    localparam STATE_VAL_ACK   = 3'd4;

    // =================================================================
    // Internal registers
    // =================================================================

    reg [2:0] state;
    reg [2:0] next_state;

    reg [DATA_WIDTH-1:0] command;
    reg [DATA_WIDTH-1:0] next_command;

    reg [DATA_WIDTH-1:0] value;
    reg [DATA_WIDTH-1:0] next_value;

    // =================================================================
    // State register
    // =================================================================

    always @(posedge i_clk) begin
        if (i_reset) begin
            state   <= STATE_IDLE;
            command <= {DATA_WIDTH{1'b0}};
            value   <= {DATA_WIDTH{1'b0}};
        end
        else begin
            state   <= next_state;
            command <= next_command;
            value   <= next_value;
        end
    end

    // =================================================================
    // Outputs
    // =================================================================

    // Keep the captured value available to the datapath.
    assign_value:
    always @(*) begin
        o_value = value;
    end

    // =================================================================
    // Next-state and control logic
    // =================================================================

    always @(*) begin

        // Defaults
        next_state   = state;
        next_command = command;
        next_value   = value;

        o_rx_read      = 1'b0;
        o_enable_a     = 1'b0;
        o_enable_b     = 1'b0;
        o_enable_op    = 1'b0;
        o_command_done = 1'b0;

        case (state)

            // ---------------------------------------------------------
            // Wait for a command byte
            // ---------------------------------------------------------

            STATE_IDLE: begin
                if (!i_rx_empty) begin

                    // Store the command before consuming the byte.
                    next_command = i_rx_data;

                    o_rx_read = 1'b1;

                    next_state = STATE_CMD_ACK;
                end
            end

            // ---------------------------------------------------------
            // Wait until the command byte has been consumed
            // ---------------------------------------------------------

            STATE_CMD_ACK: begin
                if (i_rx_empty)
                    next_state = STATE_WAIT_DATA;
            end

            // ---------------------------------------------------------
            // Wait for the value byte
            // ---------------------------------------------------------

            STATE_WAIT_DATA: begin
                if (!i_rx_empty) begin

                    // Capture the value before consuming it.
                    next_value = i_rx_data;

                    o_rx_read = 1'b1;

                    next_state = STATE_LOAD;
                end
            end

            // ---------------------------------------------------------
            // Load the selected register
            // ---------------------------------------------------------

            STATE_LOAD: begin

                case (command)
                    8'd0: o_enable_a  = 1'b1;
                    8'd1: o_enable_b  = 1'b1;
                    8'd2: o_enable_op = 1'b1;
                    default: ;
                endcase

                next_state = STATE_VAL_ACK;
            end

            // ---------------------------------------------------------
            // Wait until the value byte has been consumed
            // ---------------------------------------------------------

            STATE_VAL_ACK: begin
                if (i_rx_empty) begin

                    // The complete [COMMAND][VALUE] transaction
                    // has now finished.
                    o_command_done = 1'b1;

                    next_state = STATE_IDLE;
                end
            end

            default: begin
                next_state = STATE_IDLE;
            end

        endcase
    end

endmodule