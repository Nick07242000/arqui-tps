`timescale 1ns/1ps

module tb_uart_tx;

    localparam DATA_BITS       = 8;
    localparam OVERSAMPLE_RATE = 16;
    localparam STOP_BIT_TICKS  = 16;
    localparam FRAME_TICKS     = OVERSAMPLE_RATE + DATA_BITS*OVERSAMPLE_RATE + STOP_BIT_TICKS;

    reg                   i_clk      = 0;
    reg                   i_reset    = 1;
    reg                   i_tx_start = 0;
    reg [DATA_BITS-1:0]   i_data_in  = 0;
    wire                  o_tx_done;
    wire                  o_tx;

    integer errors = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s (time=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    // One clock cycle = one baud tick
    wire i_baud_tick = 1'b1;

    uart_tx #(
        .DATA_BITS(DATA_BITS),
        .OVERSAMPLE_RATE(OVERSAMPLE_RATE),
        .STOP_BIT_TICKS(STOP_BIT_TICKS)
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_tx_start(i_tx_start),
        .i_baud_tick(i_baud_tick),
        .i_data_in(i_data_in),
        .o_tx_done(o_tx_done),
        .o_tx(o_tx)
    );

    always #5 i_clk = ~i_clk;

    integer done_count = 0;
    always @(posedge i_clk) if (o_tx_done) done_count = done_count + 1;

    // Sends one byte, decodes the o_tx waveform bit-by-bit and checks it
    task send_and_check(input [DATA_BITS-1:0] data);
        integer i;
        integer done_before;
        reg     sampled;
        begin
            done_before = done_count;

            @(posedge i_clk);
            i_data_in  = data;
            i_tx_start = 1'b1;
            @(posedge i_clk);
            i_tx_start = 1'b0;

            // Idle level should be high before the start bit begins.
            check(o_tx == 1'b1, "o_tx not idle-high right before start bit");

            // Start bit: held low for one full bit period.
            repeat (OVERSAMPLE_RATE/2) @(posedge i_clk);
            check(o_tx == 1'b0, "start bit not low");
            repeat (OVERSAMPLE_RATE/2) @(posedge i_clk);

            // Data bits, LSB first.
            for (i = 0; i < DATA_BITS; i = i + 1) begin
                repeat (OVERSAMPLE_RATE/2) @(posedge i_clk);
                sampled = o_tx;
                check(sampled == data[i], "data bit mismatch on the wire");
                repeat (OVERSAMPLE_RATE/2) @(posedge i_clk);
            end

            // Stop bit: held high.
            repeat (STOP_BIT_TICKS/2) @(posedge i_clk);
            check(o_tx == 1'b1, "stop bit not high");
            repeat (STOP_BIT_TICKS/2) @(posedge i_clk);

            @(posedge i_clk);
            check(done_count == done_before + 1, "o_tx_done did not pulse exactly once for the frame");
        end
    endtask

    initial begin
        repeat (3) @(posedge i_clk);
        i_reset = 0;
        @(posedge i_clk);

        send_and_check(8'h55);
        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);

        // Re-asserting i_tx_start while a frame is already in flight must not restart
        fork
            send_and_check(8'h3C);
            begin
                repeat (OVERSAMPLE_RATE + 3) @(posedge i_clk);
                i_tx_start = 1'b1;
                i_data_in  = 8'hFF; // different data than the in-flight frame
                @(posedge i_clk);
                i_tx_start = 1'b0;
            end
        join

        if (errors == 0)
            $display("PASS: uart_tx");
        else
            $display("DONE: uart_tx with %0d error(s)", errors);

        $finish;
    end

endmodule