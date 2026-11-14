`timescale 1ns / 1ps
`include "program_loader_defs.vh"

// -----------------------------------------------------------------------------
// Carga de programa: recibe el programa a bytes y lo escribe en program_memory.
// -----------------------------------------------------------------------------
module program_loader #(
    parameter ADDR_WIDTH        = 10,          // ancho del indice de palabra de program_memory
    parameter RX_TIMEOUT_CYCLES = 2_700_000    // silencio maximo entre bytes (100 ms a 27 MHz)
) (
    input  wire                  i_clk,
    input  wire                  i_reset,                 // reset de sistema

    // ---- Orden de carga y bytes del payload (los entrega la Debug Unit) -----
    input  wire                  i_load_start,            // pulso: comienza una carga
    input  wire [15:0]           i_payload_length_bytes,  // LEN del mensaje, valido con i_load_start
    input  wire                  i_byte_valid,            // pulso: i_byte_data es un byte del payload
    input  wire [7:0]            i_byte_data,

    // ---- Puerto de escritura de program_memory ------------------------------
    output wire                  o_imem_write_enable,
    output wire [ADDR_WIDTH-1:0] o_imem_write_word_addr,
    output wire [31:0]           o_imem_write_data,

    // ---- Estado de la carga -------------------------------------------------
    output wire                  o_cpu_reset,             // CPU en reset mientras se reescribe la imagen
    output reg                   o_program_valid,         // hay una imagen completa y validada
    output reg  [ADDR_WIDTH:0]   o_n_words,               // largo de la imagen (0 si no es valida)
    output reg                   o_load_finished,         // pulso: la carga termino (bien o mal)
    output reg  [1:0]            o_load_error_code        // resultado, ver program_loader_defs.vh
);

    // -------------------------------------------------------------------------
    // Constantes y estados
    // -------------------------------------------------------------------------
    localparam MEMORY_DEPTH_WORDS    = 1 << ADDR_WIDTH;
    localparam HEADER_BYTES          = 2;                       // campo N_WORDS
    localparam TIMEOUT_COUNTER_WIDTH = $clog2(RX_TIMEOUT_CYCLES + 1);

    localparam [2:0] STATE_IDLE               = 3'd0,
                     STATE_RECEIVE_COUNT_LOW  = 3'd1,
                     STATE_RECEIVE_COUNT_HIGH = 3'd2,
                     STATE_RECEIVE_WORDS      = 3'd3,
                     STATE_DISCARD_BYTES      = 3'd4;           // error: se consume el resto del mensaje

    // -------------------------------------------------------------------------
    // Registros internos
    // -------------------------------------------------------------------------
    reg [2:0]                       state;
    reg [15:0]                      payload_bytes_remaining;
    reg [7:0]                       word_count_low_byte;
    reg [ADDR_WIDTH:0]              declared_word_count;
    reg [ADDR_WIDTH-1:0]            write_word_index;
    reg [1:0]                       byte_lane;                  // byte de la palabra en curso (0 a 3)
    reg [23:0]                      partial_word;               // bytes 0 a 2 de la palabra en curso
    reg [TIMEOUT_COUNTER_WIDTH-1:0] silent_cycle_count;         // ciclos sin recibir un byte

    // -------------------------------------------------------------------------
    // Condiciones derivadas
    // -------------------------------------------------------------------------
    wire timeout_expired = (silent_cycle_count == RX_TIMEOUT_CYCLES);

    wire [15:0] payload_bytes_after_this_byte = payload_bytes_remaining - 16'd1;
    wire        is_last_payload_byte          = (payload_bytes_after_this_byte == 16'd0);

    // Validacion del encabezado, se evalua al llegar el segundo byte de N_WORDS
    wire [15:0] header_word_count        = {i_byte_data, word_count_low_byte};
    wire        word_count_is_valid      = (header_word_count != 16'd0)
                                        && (header_word_count <= MEMORY_DEPTH_WORDS);
    wire        payload_length_matches   = ({2'b00, payload_bytes_after_this_byte}
                                            == {header_word_count, 2'b00});

    wire        payload_is_too_short     = (i_payload_length_bytes < HEADER_BYTES);

    // -------------------------------------------------------------------------
    // Salidas combinacionales
    // -------------------------------------------------------------------------
    // La palabra se escribe cuando llega su cuarto byte
    assign o_imem_write_enable    = (state == STATE_RECEIVE_WORDS)
                                 && i_byte_valid
                                 && (byte_lane == 2'd3)
                                 && !timeout_expired;
    assign o_imem_write_word_addr = write_word_index;
    assign o_imem_write_data      = {i_byte_data, partial_word};

    // La CPU se resetea recien cuando la imagen empieza a reescribirse
    assign o_cpu_reset            = (state == STATE_RECEIVE_WORDS);

    // -------------------------------------------------------------------------
    // Secuencia de carga
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        o_load_finished <= 1'b0;

        if (i_reset) begin
            state                   <= STATE_IDLE;
            o_program_valid         <= 1'b0;
            o_n_words               <= {(ADDR_WIDTH+1){1'b0}};
            o_load_error_code       <= `LOAD_ERROR_NONE;
            payload_bytes_remaining <= 16'd0;
            write_word_index        <= {ADDR_WIDTH{1'b0}};
            byte_lane               <= 2'd0;
            silent_cycle_count      <= {TIMEOUT_COUNTER_WIDTH{1'b0}};

        end else if (state == STATE_IDLE) begin
            if (i_load_start) begin
                o_load_error_code       <= payload_is_too_short ? `LOAD_ERROR_LENGTH
                                                                : `LOAD_ERROR_NONE;
                payload_bytes_remaining <= i_payload_length_bytes;
                write_word_index        <= {ADDR_WIDTH{1'b0}};
                byte_lane               <= 2'd0;
                silent_cycle_count      <= {TIMEOUT_COUNTER_WIDTH{1'b0}};
                state                   <= payload_is_too_short ? STATE_DISCARD_BYTES
                                                                : STATE_RECEIVE_COUNT_LOW;
            end

        end else if (timeout_expired) begin
            o_load_error_code <= `LOAD_ERROR_TIMEOUT;
            o_load_finished   <= 1'b1;
            state             <= STATE_IDLE;

        end else begin
            silent_cycle_count <= i_byte_valid ? {TIMEOUT_COUNTER_WIDTH{1'b0}}
                                               : silent_cycle_count + 1'b1;

            case (state)
                STATE_RECEIVE_COUNT_LOW: if (i_byte_valid) begin
                    word_count_low_byte     <= i_byte_data;
                    payload_bytes_remaining <= payload_bytes_after_this_byte;
                    state                   <= STATE_RECEIVE_COUNT_HIGH;
                end

                // Se valida todo el encabezado antes de tocar el programa anterior
                STATE_RECEIVE_COUNT_HIGH: if (i_byte_valid) begin
                    payload_bytes_remaining <= payload_bytes_after_this_byte;

                    if (!word_count_is_valid) begin
                        o_load_error_code <= `LOAD_ERROR_ARGUMENT;
                        state             <= STATE_DISCARD_BYTES;
                    end else if (!payload_length_matches) begin
                        o_load_error_code <= `LOAD_ERROR_LENGTH;
                        state             <= STATE_DISCARD_BYTES;
                    end else begin
                        // Encabezado valido: desde aca el programa anterior se pierde
                        o_program_valid     <= 1'b0;
                        o_n_words           <= {(ADDR_WIDTH+1){1'b0}};
                        declared_word_count <= header_word_count[ADDR_WIDTH:0];
                        state               <= STATE_RECEIVE_WORDS;
                    end
                end

                STATE_RECEIVE_WORDS: if (i_byte_valid) begin
                    payload_bytes_remaining <= payload_bytes_after_this_byte;
                    byte_lane               <= byte_lane + 2'd1;

                    if (byte_lane != 2'd3) begin
                        partial_word <= {i_byte_data, partial_word[23:8]};
                    end else begin
                        write_word_index <= write_word_index + 1'b1;

                        if (is_last_payload_byte) begin
                            o_program_valid <= 1'b1;
                            o_n_words       <= declared_word_count;
                            o_load_finished <= 1'b1;
                            state           <= STATE_IDLE;
                        end
                    end
                end

                // Se consume el mensaje completo para no desincronizar el flujo
                STATE_DISCARD_BYTES: begin
                    if (payload_bytes_remaining == 16'd0) begin
                        o_load_finished <= 1'b1;
                        state           <= STATE_IDLE;
                    end else if (i_byte_valid) begin
                        payload_bytes_remaining <= payload_bytes_after_this_byte;
                    end
                end
            endcase
        end
    end

endmodule