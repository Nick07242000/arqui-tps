module uart_tx #(
    parameter integer DATA_BITS       = 8,
    parameter integer OVERSAMPLE_RATE = 16,
    parameter integer STOP_BIT_TICKS  = 16
)(
    input  wire                  i_clk,
    input  wire                  i_reset,
    input  wire                  i_tx_start,
    input  wire                  i_baud_tick,
    input  wire [DATA_BITS-1:0]  i_data_in,

    output reg                   o_tx_done,
    output wire                  o_tx
);

// Transmitter states
    localparam [1:0]
        STATE_IDLE  = 2'b00,
        STATE_START = 2'b01,
        STATE_DATA  = 2'b10,
        STATE_STOP  = 2'b11;

// Counter sizes

    // Width needed for the tick counter.
    localparam integer TICK_COUNT_WIDTH =
        (OVERSAMPLE_RATE <= 1) ? 1 : $clog2(OVERSAMPLE_RATE);

    // Width needed for the data-bit counter.
    localparam integer BIT_INDEX_WIDTH =
        (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);


// Transmitter registers
    reg [1:0]                   state;

    reg [TICK_COUNT_WIDTH-1:0]  tick_count;
    // Counts baud ticks within the current UART bit.

    reg [BIT_INDEX_WIDTH-1:0]   bit_index;
    // Keeps track of which data bit is being transmitted.

    reg [DATA_BITS-1:0]         data_reg;
    // Stores the data currently being transmitted.

    reg                         tx_reg;
    // Stores the current UART output level.

// State handlers

    // Keep TX high while idle.
    // When a transmission is requested, store the input data
    // and begin the start bit.
    task handle_idle;
        begin
            tx_reg <= 1'b1;

            if (i_tx_start) begin
                state      <= STATE_START;
                tick_count <= 0;
                data_reg   <= i_data_in;
            end
        end
    endtask


    // Transmit the start bit by holding TX low for one
    // complete UART bit period.
    task handle_start;
        begin
            tx_reg <= 1'b0;

            if (i_baud_tick) begin
                if (tick_count == OVERSAMPLE_RATE - 1) begin
                    state      <= STATE_DATA;
                    tick_count <= 0;
                    bit_index  <= 0;
                end
                else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


    // Transmit one data bit at a time.
    // UART sends the least significant bit first.
    // The data register is shifted right after each bit.
    task handle_data;
        begin
            tx_reg <= data_reg[0];

            if (i_baud_tick) begin
                if (tick_count == OVERSAMPLE_RATE - 1) begin
                    tick_count <= 0;
                    data_reg   <= data_reg >> 1;

                    // Check whether this was the last data bit.
                    if (bit_index == DATA_BITS - 1) begin
                        state <= STATE_STOP;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
                else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


    // Transmit the stop bit by holding TX high.
    // Once the stop bit is complete, signal that the
    // transmission has finished.
    task handle_stop;
        begin
            tx_reg <= 1'b1;

            if (i_baud_tick) begin
                if (tick_count == STOP_BIT_TICKS - 1) begin
                    state     <= STATE_IDLE;
                    o_tx_done <= 1'b1;
                end
                else begin
                    tick_count <= tick_count + 1'b1;
                end
            end
        end
    endtask


// UART transmitter
    always @(posedge i_clk) begin

        if (i_reset) begin
            state      <= STATE_IDLE;
            tick_count <= 0;
            bit_index  <= 0;
            data_reg   <= 0;
            tx_reg     <= 1'b1;
            o_tx_done  <= 1'b0;
        end
        else begin

            // tx_done is normally low.
            // It is set high for one clock cycle when
            // the complete frame has been transmitted.
            o_tx_done <= 1'b0;

            case (state)

                STATE_IDLE:  handle_idle();
                STATE_START: handle_start();
                STATE_DATA:  handle_data();
                STATE_STOP:  handle_stop();
                default: state <= STATE_IDLE;

            endcase
        end
    end


    // Connect the internal TX register to the module output.
    assign o_tx = tx_reg;

endmodule
