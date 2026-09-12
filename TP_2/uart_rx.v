module uart_rx #(
    parameter DBIT = 8,    // data bits
    parameter SB_TICK = 16 // ticks for stop bit
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    input  wire       s_tick,
    output reg        rx_done_tick,
    output wire [7:0] dout
);

    localparam [1:0]
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;

    reg [1:0] state_reg;
    reg [1:0] state_next;
    reg [3:0] s_reg;
    reg [3:0] s_next; // sampling counter
    reg [2:0] n_reg;
    reg [2:0] n_next; // bit counter
    reg [7:0] b_reg;
    reg [7:0] b_next; // shift register

    // State and data registers
    always @(posedge clk) begin
        if (reset) begin
            state_reg <= IDLE;
            s_reg     <= 0;
            n_reg     <= 0;
            b_reg     <= 0;
        end else begin
            state_reg <= state_next;
            s_reg     <= s_next;
            n_reg     <= n_next;
            b_reg     <= b_next;
        end
    end

    // next-state logic and data path
    always @* begin
        state_next   = state_reg;
        rx_done_tick = 1'b0;
        s_next       = s_reg;
        n_next       = n_reg;
        b_next       = b_reg;

        case (state_reg)
            IDLE:
                if (~rx) begin
                    state_next = START;
                    s_next     = 0;
                end
            START:
                if (s_tick) begin
                    if (s_reg == 7) begin
                        state_next = DATA;
                        s_next     = 0;
                        n_next     = 0;
                    end else begin
                        s_next = s_reg + 1;
                    end
                end
            DATA:
                if (s_tick) begin
                    if (s_reg == 15) begin
                        s_next = 0;
                        b_next = {rx, b_reg[7:1]};
                        if (n_reg == (DBIT - 1))
                            state_next = STOP;
                        else
                            n_next = n_reg + 1;
                    end else begin
                        s_next = s_reg + 1;
                    end
                end
            STOP:
                if (s_tick) begin
                    if (s_reg == (SB_TICK - 1)) begin
                        state_next   = IDLE;
                        rx_done_tick = 1'b1;
                    end else begin
                        s_next = s_reg + 1;
                    end
                end
        endcase
    end

    assign dout = b_reg;

endmodule
