`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Transmisor UART 8-N-1 (8 bits de datos, sin paridad, 1 bit de stop)
// Envia un byte por pedido. o_busy vale 1 durante toda la trama, bit de stop incluido.
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter CLK_HZ    = 27_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       i_clk,
    input  wire       i_reset,            // reset sincrono
    input  wire       i_send_request,     // pulso: envia i_byte_data (se ignora si o_busy = 1)
    input  wire [7:0] i_byte_data,

    output wire       o_tx_pin,
    output reg        o_busy
);

    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------
    localparam DATA_BITS           = 8;
    localparam FRAME_BITS          = 1 + DATA_BITS + 1;                      // start + datos + stop
    localparam BIT_PERIOD_CYCLES   = (CLK_HZ + BAUD_RATE / 2) / BAUD_RATE;   // redondeado
    localparam CYCLE_COUNTER_WIDTH = $clog2(BIT_PERIOD_CYCLES);

    localparam START_BIT = 1'b0;
    localparam STOP_BIT  = 1'b1;

    // -------------------------------------------------------------------------
    // Registros de la transmision
    // -------------------------------------------------------------------------
    reg [FRAME_BITS-1:0]            frame_shift_register;   // el bit [0] es el que esta en la linea
    reg [3:0]                       frame_bits_remaining;
    reg [CYCLE_COUNTER_WIDTH-1:0]   cycles_in_bit;

    // Los 1 que entran por la izquierda dejan la linea en reposo al terminar la trama
    initial begin
        frame_shift_register = {FRAME_BITS{1'b1}};
        frame_bits_remaining = 4'd0;
        cycles_in_bit        = {CYCLE_COUNTER_WIDTH{1'b0}};
        o_busy               = 1'b0;
    end

    assign o_tx_pin = frame_shift_register[0];

    wire bit_period_elapsed = (cycles_in_bit == BIT_PERIOD_CYCLES - 1);
    wire is_last_frame_bit  = (frame_bits_remaining == 4'd1);

    // -------------------------------------------------------------------------
    // Secuencia de transmision
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_reset) begin
            frame_shift_register <= {FRAME_BITS{1'b1}};
            frame_bits_remaining <= 4'd0;
            cycles_in_bit        <= {CYCLE_COUNTER_WIDTH{1'b0}};
            o_busy               <= 1'b0;

        end else if (!o_busy) begin
            if (i_send_request) begin
                frame_shift_register <= {STOP_BIT, i_byte_data, START_BIT};   // el start sale primero
                frame_bits_remaining <= FRAME_BITS;
                cycles_in_bit        <= {CYCLE_COUNTER_WIDTH{1'b0}};
                o_busy               <= 1'b1;
            end

        end else if (bit_period_elapsed) begin
            frame_shift_register <= {1'b1, frame_shift_register[FRAME_BITS-1:1]};
            frame_bits_remaining <= frame_bits_remaining - 1'b1;
            cycles_in_bit        <= {CYCLE_COUNTER_WIDTH{1'b0}};

            if (is_last_frame_bit)
                o_busy <= 1'b0;

        end else begin
            cycles_in_bit <= cycles_in_bit + 1'b1;
        end
    end

endmodule
