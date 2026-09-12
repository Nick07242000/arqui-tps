module uart_fsm (
    input  wire clk,
    input  wire rst,
    input  wire rx_empty, // high when RX FIFO is empty
    input  wire tx_full,  // high when transmitter is busy
    output reg  en_a,     // command to enable Register A
    output reg  en_b,     // command to enable Register B
    output reg  en_op,    // command to enable Register OP
    output reg  tx_start  // command to trigger UART TX
);

    localparam [2:0]
        S_LOAD_A   = 3'd0,
        S_WAIT_A   = 3'd1,
        S_LOAD_B   = 3'd2,
        S_WAIT_B   = 3'd3,
        S_LOAD_OP  = 3'd4,
        S_WAIT_OP  = 3'd5,
        S_SEND_TX  = 3'd6;

    reg [2:0] state_reg = S_LOAD_A;
    reg [2:0] state_next;

    // state register update
    always @(posedge clk) begin
        if (rst)
            state_reg <= S_LOAD_A;
        else
            state_reg <= state_next;
    end

    // next-state logic and outputs
    always @(*) begin
        state_next = state_reg;
        en_a       = 1'b0;
        en_b       = 1'b0;
        en_op      = 1'b0;
        tx_start   = 1'b0;

        case (state_reg)
            S_LOAD_A: begin
                if (~rx_empty) begin
                    en_a       = 1'b1;
                    state_next = S_WAIT_A;
                end
            end
            S_WAIT_A: begin // wait for RX FIFO to be empty before loading B
                if (rx_empty) state_next = S_LOAD_B;
            end
            
            S_LOAD_B: begin
                if (~rx_empty) begin
                    en_b       = 1'b1;
                    state_next = S_WAIT_B;
                end
            end
            S_WAIT_B: begin
                if (rx_empty) state_next = S_LOAD_OP;
            end
            
            S_LOAD_OP: begin
                if (~rx_empty) begin
                    en_op      = 1'b1;
                    state_next = S_WAIT_OP;
                end
            end
            S_WAIT_OP: begin
                if (rx_empty) state_next = S_SEND_TX;
            end
            
            S_SEND_TX: begin
                if (~tx_full) begin
                    tx_start   = 1'b1;
                    state_next = S_LOAD_A;
                end
            end
            default: state_next = S_LOAD_A;
        endcase
    end
endmodule
