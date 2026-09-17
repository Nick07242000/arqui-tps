module baud_rate_generator #(
    parameter CLK_FREQ = 27000000,
    parameter BAUD_RATE  = 9600,
    parameter OVERSAMPLE_RATE = 16
)(
    input  wire i_clk,
    input  wire i_reset,
    output wire o_tick
);
    // Number of FPGA clock cycles between UART ticks.
    localparam TICK_COUNT = CLK_FREQ / (BAUD_RATE * OVERSAMPLE_RATE);

    // Automatically calculate the number of bits needed by the counter. 
    localparam COUNTER_WIDTH = (TICK_COUNT <= 1) ? 1 : $clog2(TICK_COUNT);
    
    // Counter 
    reg [COUNTER_WIDTH-1:0] counter;

    // Counter increments every FPGA clock cycle.
    always @(posedge i_clk) begin
        if (i_reset)
            counter <= 0;
        else if (counter == TICK_COUNT - 1) 
            counter <= 0; 
        else 
            counter <= counter + 1'b1;
    end

    // One-clock-cycle pulse when the counter reaches its limit. 
    assign o_tick = (counter == TICK_COUNT - 1);

endmodule
