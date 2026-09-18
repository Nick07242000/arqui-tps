`timescale 1ns/1ps

module tb_uart_baud;

    // Small parameters so ticks arrive quickly in simulation.
    localparam CLK_FREQ        = 5;
    localparam BAUD_RATE       = 1;
    localparam OVERSAMPLE_RATE = 1;
    localparam TICK_COUNT      = CLK_FREQ / (BAUD_RATE * OVERSAMPLE_RATE); // = 5

    reg  i_clk   = 0;
    reg  i_reset = 1;
    wire o_tick;

    integer errors = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s (time=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    baud_rate_generator #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE)
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_tick(o_tick)
    );

    always #5 i_clk = ~i_clk;

    integer i;
    integer gap;

    // Waits from "just after a tick" to the next tick and returns the gap.
    task measure_period(output integer period);
        begin
            @(posedge i_clk);
            period = 1;
            while (o_tick !== 1'b1) begin
                @(posedge i_clk);
                period = period + 1;
            end
        end
    endtask

    initial begin
        // Hold reset a few cycles, then release it.
        repeat (3) @(posedge i_clk);
        i_reset = 0;

        // Sync to the first tick.
        while (o_tick !== 1'b1) @(posedge i_clk);

        // Tick should fire exactly once every TICK_COUNT cycles, repeatedly.
        for (i = 0; i < 4; i = i + 1) begin
            measure_period(gap);
            check(gap == TICK_COUNT, "tick period is not TICK_COUNT cycles");
        end

        // A reset asserted mid-count should restart the period from zero.
        repeat (2) @(posedge i_clk);
        i_reset = 1;
        @(posedge i_clk);
        i_reset = 0;
        while (o_tick !== 1'b1) @(posedge i_clk);
        measure_period(gap);
        check(gap == TICK_COUNT, "tick period wrong right after reset");

        if (errors == 0)
            $display("PASS: uart_baud");
        else
            $display("DONE: uart_baud with %0d error(s)", errors);

        $finish;
    end

endmodule