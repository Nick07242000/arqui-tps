module uart_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_empty, // high when RX FIFO is empty
    input  wire [7:0] rx_data,  // data from UART RX to decode command
    input  wire       tx_full,  // high when transmitter is busy
    output reg        rx_read,  // command to consume UART RX byte
    output reg        en_a,     // command to enable register A
    output reg        en_b,     // command to enable register B
    output reg        en_op,    // command to enable register OP
    output reg        tx_start, // command to trigger UART TX
    output wire [2:0] tx_sel    // selects which register to transmit (0 to 4)
);

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_CMD_ACK   = 4'd1,
        S_WAIT_VAL  = 4'd2,
        S_VAL_ACK   = 4'd3,
        S_TX_LOAD   = 4'd4,
        S_TX_START  = 4'd5,
        S_TX_W1     = 4'd6,
        S_TX_W2     = 4'd7;

    reg [3:0] state_reg;
    reg [3:0] state_next;
    reg [7:0] cmd_reg;       // stores the target register (0, 1, or 2)
    reg [7:0] cmd_next;
    reg [2:0] tx_count;      // counts from 0 to 4 for the 5 TX frames
    reg [2:0] tx_count_next;

    // initial values for registers
    initial begin
        state_reg = S_IDLE;
        cmd_reg   = 8'd0;
        tx_count  = 3'd0;
    end

    // state register update
    always @(posedge clk) begin
        if (rst) begin
            state_reg <= S_IDLE;
            cmd_reg   <= 8'd0;
            tx_count  <= 3'd0;
        end else begin
            state_reg <= state_next;
            cmd_reg   <= cmd_next;
            tx_count  <= tx_count_next;
        end
    end

    // link the transmission selector to our counter
    assign tx_sel = tx_count;

    // next-state logic and outputs
    always @(*) begin
        // default values to prevent latches
        state_next    = state_reg;
        cmd_next      = cmd_reg;
        tx_count_next = tx_count;
        
        rx_read       = 1'b0;
        en_a          = 1'b0;
        en_b          = 1'b0;
        en_op         = 1'b0;
        tx_start      = 1'b0;

        case (state_reg)
            S_IDLE: begin
                tx_count_next = 3'd0; // reset TX sequence counter
                if (~rx_empty) begin
                    cmd_next   = rx_data; // save target command
                    rx_read    = 1'b1;    // consume byte
                    state_next = S_CMD_ACK;
                end
            end
            
            S_CMD_ACK: begin
                // wait for RX FIFO to be empty before waiting for the value
                if (rx_empty) state_next = S_WAIT_VAL;
            end
            
            S_WAIT_VAL: begin
                if (~rx_empty) begin
                    // route the value to the correct register
                    if (cmd_reg == 8'd0)      en_a  = 1'b1;
                    else if (cmd_reg == 8'd1) en_b  = 1'b1;
                    else if (cmd_reg == 8'd2) en_op = 1'b1;
                    
                    rx_read    = 1'b1; // consume value byte
                    state_next = S_VAL_ACK;
                end
            end
            
            S_VAL_ACK: begin
                if (rx_empty) state_next = S_TX_LOAD;
            end
            
            // TX SEQUENCE BURST (5 BYTES)
            S_TX_LOAD: begin
                // wait until TX is ready to accept new data
                if (~tx_full) begin
                    state_next = S_TX_START;
                end
            end
            
            S_TX_START: begin
                tx_start   = 1'b1;
                state_next = S_TX_W1;
            end
            
            S_TX_W1: begin
                // dummy wait state to ensure tx_full goes high
                state_next = S_TX_W2;
            end
            
            S_TX_W2: begin
                // wait for TX to finish sending current byte
                if (~tx_full) begin
                    if (tx_count == 3'd4) begin
                        // all 5 bytes sent, return to idle
                        state_next = S_IDLE;
                    end else begin
                        // increment counter and send next byte
                        tx_count_next = tx_count + 3'd1;
                        state_next    = S_TX_LOAD;
                    end
                end
            end
            
            default: state_next = S_IDLE;
        endcase
    end

endmodule
