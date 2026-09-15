// UART Receiver
// 8N1 format, LSB first.
// Uses the main FPGA clock and a baud-rate tick for UART timing.

module uart_rx #(
    parameter integer DATA_BITS       = 8,
    parameter integer OVERSAMPLE_RATE = 16,
    parameter integer STOP_BIT_TICKS  = 16
)(
    input  wire                  i_clk,
    input  wire                  i_reset,
    input  wire                  i_rx,
    input  wire                  i_baud_tick,

    output reg                   o_rx_done,
    output wire [DATA_BITS-1:0]  o_data_out
);

    //============================================================
    // Receiver states
    //============================================================
    localparam [1:0]
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;


    //============================================================
    // Counter sizes
    //============================================================

    // Number of ticks needed to reach the middle of a bit.
    localparam integer HALF_BIT_TICKS = OVERSAMPLE_RATE / 2;

    // Width needed for the tick counter.
    localparam integer TICK_COUNT_WIDTH =
        (OVERSAMPLE_RATE <= 1) ? 1 : $clog2(OVERSAMPLE_RATE);

    // Width needed for the data-bit counter.
    localparam integer BIT_INDEX_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);


    //============================================================
    // Receiver registers
    //============================================================

    reg [1:0]                    state;

    reg [TICK_COUNT_WIDTH-1:0]   tick_count;
    // Counts baud ticks within the current UART bit.

    reg [BIT_INDEX_WIDTH-1:0]    bit_index;
    // Keeps track of which data bit is being received.

    reg [DATA_BITS-1:0]          data_reg;
    // Stores the received byte.


    //============================================================
    // State handlers
    //============================================================

    // Wait for RX to go low, indicating the beginning of
    // a new UART frame.
    task handle_idle;
        begin
            if (!i_rx) begin
                state      <= START;
                tick_count <= 0;
            end
        end
    endtask


    // Wait half of a UART bit so that the first data bit
    // can be sampled near the center of its bit period.
    task handle_start;
        begin
            if (i_baud_tick) begin
                if (tick_count == HALF_BIT_TICKS - 1) begin

                    // Start bit is confirmed.
                    state      <= DATA;
                    tick_count <= 0;
                    bit_index  <= 0;

                end else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


    // Wait one complete UART bit and sample the next data bit.
    // UART sends data least significant bit first.
    task handle_data;
        begin
            if (i_baud_tick) begin
                if (tick_count == OVERSAMPLE_RATE - 1) begin

                    tick_count <= 0;

                    // Shift the received bit into the data register.
                    data_reg <= {i_rx, data_reg[DATA_BITS-1:1]};

                    // Check whether this was the last data bit.
                    if (bit_index == DATA_BITS - 1) begin
                        state <= STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end

                end else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


    // Wait through the stop bit. Once the stop bit is complete,
    // signal that a complete byte has been received.
    task handle_stop;
        begin
            if (i_baud_tick) begin
                if (tick_count == STOP_BIT_TICKS - 1) begin

                    state    <= IDLE;
                    o_rx_done <= 1'b1;

                end else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


    //============================================================
    // UART receiver
    //============================================================

    always @(posedge i_clk) begin

        if (i_reset) begin

            state       <= IDLE;
            tick_count  <= 0;
            bit_index   <= 0;
            data_reg    <= 0;
            o_rx_done   <= 1'b0;

        end else begin

            // rx_done is normally low.
            // It is set high for one clock cycle when a byte is ready.
            o_rx_done <= 1'b0;

            case (state)

                IDLE: handle_idle();
                START: handle_start();
                DATA: handle_data();
                STOP: handle_stop();
                default: state <= IDLE;

            endcase
        end
    end


    // Connect the internal data register to the module output.
    assign o_data_out = data_reg;

endmodule