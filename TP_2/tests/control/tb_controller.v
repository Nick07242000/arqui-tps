`timescale 1ns/1ps

module tb_controller;

    reg        i_clk   = 0;
    reg        i_reset = 1;

    reg        i_rx_empty = 1;
    reg [7:0]  i_rx_data  = 0;
    wire       o_rx_read;

    wire       o_enable_a;
    wire       o_enable_b;
    wire       o_enable_op;

    reg        i_tx_full = 0;
    wire       o_tx_start;

    wire [2:0] o_tx_select;

    integer errors = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                $display("FAIL: %0s (time=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    controller dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_rx_empty(i_rx_empty),
        .i_rx_data(i_rx_data),
        .o_rx_read(o_rx_read),
        .o_enable_a(o_enable_a),
        .o_enable_b(o_enable_b),
        .o_enable_op(o_enable_op),
        .i_tx_full(i_tx_full),
        .o_tx_start(o_tx_start),
        .o_tx_select(o_tx_select)
    );

    always #5 i_clk = ~i_clk;

    // Emulates the rx buffer: puts a byte on the bus and waits for it
    // to be read and acknowledged (mirrors uart_interface's protocol).
    task deliver_rx_byte(input [7:0] data);
        begin
            i_rx_data  = data;
            i_rx_empty = 1'b0;
            @(posedge i_clk); // byte is read (o_rx_read pulses) and latched here
            i_rx_empty = 1'b1;
            @(posedge i_clk); // acknowledge propagates to the FSM
        end
    endtask

    // Emulates the tx path: after o_tx_start pulses, holds tx_full for
    // a couple of cycles like a real transmission in progress.
    task emulate_tx;
        begin
            while (!o_tx_start) @(posedge i_clk);
            @(posedge i_clk);        // move into STATE_TX_DELAY
            i_tx_full = 1'b1;        // simulate the transmitter going busy
            repeat (2) @(posedge i_clk);
            i_tx_full = 1'b0;        // simulate the transmitter finishing
            @(posedge i_clk);        // let the FSM react to tx_full going low
        end
    endtask

    // Enable lines seen at the moment the value byte is accepted.
    reg seen_enable_a, seen_enable_b, seen_enable_op;
    always @(posedge i_clk) begin
        if (o_rx_read) begin
            seen_enable_a  = seen_enable_a  | o_enable_a;
            seen_enable_b  = seen_enable_b  | o_enable_b;
            seen_enable_op = seen_enable_op | o_enable_op;
        end
    end

    integer k;

    // Drives one full command: command byte -> value byte -> 5 response
    // bytes (A, B, OP, result, status), as the interface would.
    task run_command(input [7:0] cmd, input [7:0] value);
        begin
            seen_enable_a  = 1'b0;
            seen_enable_b  = 1'b0;
            seen_enable_op = 1'b0;

            deliver_rx_byte(cmd);
            deliver_rx_byte(value);

            for (k = 0; k < 5; k = k + 1) begin
                check(o_tx_select == k[2:0], "tx_select does not match the expected response index");
                emulate_tx();
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge i_clk);
        i_reset = 0;
        @(posedge i_clk);

        check(o_rx_read == 1'b0, "rx_read should be idle right after reset");
        check(o_tx_start == 1'b0, "tx_start should be idle right after reset");

        // Command 0 selects register A.
        run_command(8'd0, 8'h11);
        check(seen_enable_a,   "enable_a was never asserted for command A");
        check(!seen_enable_b,  "enable_b asserted for command A");
        check(!seen_enable_op, "enable_op asserted for command A");
        @(posedge i_clk);
        check(o_tx_select == 3'd0, "tx_select should reset to 0 back in idle");

        // Command 1 selects register B.
        run_command(8'd1, 8'h22);
        check(seen_enable_b,   "enable_b was never asserted for command B");
        check(!seen_enable_a,  "enable_a asserted for command B");
        check(!seen_enable_op, "enable_op asserted for command B");

        // Command 2 selects the opcode register.
        run_command(8'd2, 8'h05);
        check(seen_enable_op,  "enable_op was never asserted for command OP");
        check(!seen_enable_a,  "enable_a asserted for command OP");
        check(!seen_enable_b,  "enable_b asserted for command OP");

        // Unknown command: FSM must still progress through the protocol
        // (rx_read pulses, 5 responses sent) but must not enable any
        // register, since no case in the FSM matches it.
        run_command(8'd7, 8'h99);
        check(!seen_enable_a,  "enable_a asserted for an unknown command");
        check(!seen_enable_b,  "enable_b asserted for an unknown command");
        check(!seen_enable_op, "enable_op asserted for an unknown command");

        if (errors == 0)
            $display("PASS: controller");
        else
            $display("DONE: controller with %0d error(s)", errors);

        $finish;
    end

endmodule