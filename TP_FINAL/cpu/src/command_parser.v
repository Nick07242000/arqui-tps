`timescale 1ns / 1ps
`include "protocol_defs.vh"
`include "execution_defs.vh"
`include "program_loader_defs.vh"

// -----------------------------------------------------------------------------
// Parser del protocolo de comandos: recibe [CMD][LEN:2 LE][PAYLOAD], valida el
// mensaje, ordena la accion y pide la respuesta [STATUS][LEN][PAYLOAD].
// -----------------------------------------------------------------------------
module command_parser #(
    parameter ADDR_WIDTH                = 10,          // ancho del indice de palabra de las memorias
    parameter RX_TIMEOUT_CYCLES         = 2_700_000,   // silencio maximo dentro de un mensaje (100 ms a 27 MHz)
    parameter COMPLETION_TIMEOUT_CYCLES = 32           // espera maxima a que el controlador conteste
) (
    input  wire        i_clk,
    input  wire        i_reset,                        // reset de sistema

    // ---- Bytes recibidos (uart_rx) ------------------------------------------
    input  wire        i_rx_byte_valid,
    input  wire [7:0]  i_rx_byte_data,
    input  wire        i_rx_framing_error,

    // ---- Estado del sistema (execution_controller) --------------------------
    input  wire [2:0]  i_system_state,

    // ---- Ordenes RUN, STEP y RESET (pulsos de un ciclo) ---------------------
    output reg         o_run_request,
    output reg         o_step_request,
    output reg         o_reset_request,
    input  wire        i_command_finished,
    input  wire [1:0]  i_command_result,

    // ---- Carga de programa (program_loader) ---------------------------------
    output reg         o_load_start,                   // pulso: comienza una carga
    output wire [15:0] o_load_payload_length_bytes,    // LEN del mensaje, valido con o_load_start
    output wire        o_load_byte_valid,              // pulso: o_load_byte_data es un byte del payload
    output wire [7:0]  o_load_byte_data,
    input  wire        i_load_finished,
    input  wire [1:0]  i_load_error_code,

    // ---- Comando en curso y argumentos de GET_MEMORY ------------------------
    output reg  [7:0]  o_command_code,                 // estable hasta el mensaje siguiente
    output wire [15:0] o_memory_start_word,
    output wire [15:0] o_memory_word_count,

    // ---- Respuesta (response_sender) ----------------------------------------
    output reg         o_response_request,             // pulso: enviar la respuesta
    output reg  [7:0]  o_response_status,
    output reg  [15:0] o_response_payload_length_bytes,
    input  wire        i_response_finished             // pulso: el ultimo byte termino de salir
);

    // -------------------------------------------------------------------------
    // Constantes y estados
    // -------------------------------------------------------------------------
    localparam MEMORY_DEPTH_WORDS       = 1 << ADDR_WIDTH;
    localparam MAX_MESSAGE_LENGTH_BYTES = 2 + 4 * MEMORY_DEPTH_WORDS;   // LOAD_PROGRAM completo
    localparam GET_MEMORY_LENGTH_BYTES  = 4;                            // start_word:u16 + count:u16
    localparam ARGUMENT_BYTES           = 4;

    localparam SILENCE_COUNTER_WIDTH    = $clog2(RX_TIMEOUT_CYCLES + 1);
    localparam COMPLETION_COUNTER_WIDTH = $clog2(COMPLETION_TIMEOUT_CYCLES + 1);

    localparam RESYNC_AFTER_RESPONSE = 1'b1;   // tras responder, ignorar bytes hasta un silencio
    localparam NO_RESYNC             = 1'b0;

    localparam [3:0] STATE_WAIT_COMMAND          = 4'd0,
                     STATE_RECEIVE_LENGTH_LOW    = 4'd1,
                     STATE_RECEIVE_LENGTH_HIGH   = 4'd2,
                     STATE_RECEIVE_PAYLOAD       = 4'd3,
                     STATE_FORWARD_LOAD          = 4'd4,    // los bytes pasan al program_loader
                     STATE_EXECUTE               = 4'd5,
                     STATE_WAIT_COMPLETION       = 4'd6,    // RUN, STEP o RESET en curso
                     STATE_WAIT_RESPONSE_SENT    = 4'd7,
                     STATE_DISCARD_UNTIL_SILENCE = 4'd8;

    // -------------------------------------------------------------------------
    // Registros internos
    // -------------------------------------------------------------------------
    reg [3:0]                         state;
    reg [7:0]                         length_low_byte;
    reg [15:0]                        message_length;           // LEN declarado en el encabezado
    reg [15:0]                        payload_bytes_received;
    reg [8*ARGUMENT_BYTES-1:0]        argument_bytes;           // primeros bytes del payload, en orden LE
    reg                               resync_after_response;
    reg [SILENCE_COUNTER_WIDTH-1:0]   silent_cycle_count;       // ciclos sin recibir nada
    reg [COMPLETION_COUNTER_WIDTH-1:0] completion_wait_cycles;  // ciclos esperando al controlador

    // -------------------------------------------------------------------------
    // Decodificacion del comando en curso
    // -------------------------------------------------------------------------
    wire command_is_load_program = (o_command_code == `COMMAND_LOAD_PROGRAM);
    wire command_is_reset        = (o_command_code == `COMMAND_RESET);
    wire command_is_run          = (o_command_code == `COMMAND_RUN);
    wire command_is_step         = (o_command_code == `COMMAND_STEP);
    wire command_is_get_status   = (o_command_code == `COMMAND_GET_STATUS);
    wire command_is_get_regs     = (o_command_code == `COMMAND_GET_REGS);
    wire command_is_get_pipeline = (o_command_code == `COMMAND_GET_PIPELINE);
    wire command_is_get_memory   = (o_command_code == `COMMAND_GET_MEMORY);

    wire command_is_known = command_is_load_program || command_is_reset || command_is_run
                         || command_is_step         || command_is_get_status
                         || command_is_get_regs     || command_is_get_pipeline
                         || command_is_get_memory;

    // Las consultas de datos no se atienden con la CPU corriendo
    wire command_needs_stopped_cpu = command_is_get_regs || command_is_get_pipeline
                                  || command_is_get_memory;

    // -------------------------------------------------------------------------
    // Condiciones derivadas
    // -------------------------------------------------------------------------
    wire cpu_is_running = (i_system_state == `EXEC_STATE_RUNNING);

    wire [15:0] declared_length               = {i_rx_byte_data, length_low_byte};
    wire [15:0] payload_bytes_after_this_byte = payload_bytes_received + 16'd1;

    wire load_can_start = command_is_load_program && !cpu_is_running;

    // Un mensaje esta en curso desde que llega CMD hasta que llega su ultimo byte
    wire message_is_in_progress = (state == STATE_RECEIVE_LENGTH_LOW)
                               || (state == STATE_RECEIVE_LENGTH_HIGH)
                               || (state == STATE_RECEIVE_PAYLOAD);

    wire rx_activity           = i_rx_byte_valid || i_rx_framing_error;
    wire silence_is_measured   = message_is_in_progress || (state == STATE_DISCARD_UNTIL_SILENCE);
    wire silence_timeout_expired     = (silent_cycle_count == RX_TIMEOUT_CYCLES);
    wire completion_timeout_expired  = (completion_wait_cycles == COMPLETION_TIMEOUT_CYCLES);

    // Un framing error aborta el mensaje, tambien si aun no llego CMD
    wire framing_error_aborts_message = i_rx_framing_error
                                     && ((state == STATE_WAIT_COMMAND) || message_is_in_progress);
    wire silence_aborts_message       = message_is_in_progress && silence_timeout_expired;

    // -------------------------------------------------------------------------
    // Los bytes de LOAD_PROGRAM pasan tal cual al program_loader
    // -------------------------------------------------------------------------
    assign o_load_payload_length_bytes = message_length;
    assign o_load_byte_valid           = i_rx_byte_valid && (state == STATE_FORWARD_LOAD);
    assign o_load_byte_data            = i_rx_byte_data;

    // -------------------------------------------------------------------------
    // Argumentos de GET_MEMORY
    // -------------------------------------------------------------------------
    assign o_memory_start_word = argument_bytes[15:0];
    assign o_memory_word_count = argument_bytes[31:16];

    // 17 bits: la suma de dos u16 no puede desbordar y parecer un rango valido
    wire [16:0] memory_end_word = {1'b0, o_memory_start_word} + {1'b0, o_memory_word_count};

    wire memory_range_is_valid = (o_memory_word_count != 16'd0)
                              && (memory_end_word <= MEMORY_DEPTH_WORDS);

    // -------------------------------------------------------------------------
    // Reglas de cada comando
    // -------------------------------------------------------------------------
    // Solo GET_MEMORY lleva payload; el LEN de LOAD_PROGRAM lo valida el program_loader
    wire [15:0] expected_message_length = command_is_get_memory ? GET_MEMORY_LENGTH_BYTES : 16'd0;

    wire length_is_valid     = (message_length == expected_message_length);
    wire arguments_are_valid = !command_is_get_memory || memory_range_is_valid;

    // Se valida en orden: comando, longitud, argumentos y estado
    reg [7:0] rejection_status;

    always @(*) begin
        if (!command_is_known)
            rejection_status = `STATUS_ERR_CMD;
        else if (!length_is_valid)
            rejection_status = `STATUS_ERR_LEN;
        else if (!arguments_are_valid)
            rejection_status = `STATUS_ERR_ARG;
        else if (command_needs_stopped_cpu && cpu_is_running)
            rejection_status = `STATUS_ERR_BUSY;
        else
            rejection_status = `STATUS_OK;
    end

    // -------------------------------------------------------------------------
    // Payload de una respuesta OK (las respuestas de error no llevan payload)
    // -------------------------------------------------------------------------
    wire [15:0] ok_payload_length_bytes =
        command_is_get_status   ? `PAYLOAD_LENGTH_STATUS_BYTES :
        command_is_get_regs     ? `PAYLOAD_LENGTH_REGS_BYTES :
        command_is_get_pipeline ? `PAYLOAD_LENGTH_PIPELINE_BYTES :
        command_is_get_memory   ? {o_memory_word_count[13:0], 2'b00} :    // 4 bytes por palabra
                                  `PAYLOAD_LENGTH_STATE_BYTES;

    // -------------------------------------------------------------------------
    // Resultado de RUN/STEP/RESET y de la carga, traducido a STATUS
    // -------------------------------------------------------------------------
    reg [7:0] command_result_status;

    always @(*) begin
        case (i_command_result)
            `EXEC_RESULT_OK:          command_result_status = `STATUS_OK;
            `EXEC_RESULT_BUSY:        command_result_status = `STATUS_ERR_BUSY;
            `EXEC_RESULT_NO_PROGRAM:  command_result_status = `STATUS_ERR_NO_PROGRAM;
            `EXEC_RESULT_WRONG_STATE: command_result_status = `STATUS_ERR_STATE;
            default:                  command_result_status = `STATUS_ERR_INTERNAL;
        endcase
    end

    reg [7:0] load_result_status;

    always @(*) begin
        case (i_load_error_code)
            `LOAD_ERROR_NONE:     load_result_status = `STATUS_OK;
            `LOAD_ERROR_ARGUMENT: load_result_status = `STATUS_ERR_ARG;
            `LOAD_ERROR_LENGTH:   load_result_status = `STATUS_ERR_LEN;
            `LOAD_ERROR_TIMEOUT:  load_result_status = `STATUS_ERR_TIMEOUT;
            default:              load_result_status = `STATUS_ERR_INTERNAL;
        endcase
    end

    // -------------------------------------------------------------------------
    // Pedido de respuesta: un OK lleva payload, un error no
    // -------------------------------------------------------------------------
    task respond(input [7:0] status, input needs_resync);
        begin
            o_response_status               <= status;
            o_response_payload_length_bytes <= (status == `STATUS_OK) ? ok_payload_length_bytes
                                                                      : 16'd0;
            o_response_request              <= 1'b1;
            resync_after_response           <= needs_resync;
            state                           <= STATE_WAIT_RESPONSE_SENT;
        end
    endtask

    // -------------------------------------------------------------------------
    // Secuencia del protocolo
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        // Pulsos de un ciclo: vuelven a 0 salvo que se activen mas abajo
        o_run_request      <= 1'b0;
        o_step_request     <= 1'b0;
        o_reset_request    <= 1'b0;
        o_load_start       <= 1'b0;
        o_response_request <= 1'b0;

        silent_cycle_count     <= (silence_is_measured && !rx_activity) ? silent_cycle_count + 1'b1
                                                                        : {SILENCE_COUNTER_WIDTH{1'b0}};
        completion_wait_cycles <= (state == STATE_WAIT_COMPLETION) ? completion_wait_cycles + 1'b1
                                                                   : {COMPLETION_COUNTER_WIDTH{1'b0}};

        if (i_reset) begin
            state                           <= STATE_WAIT_COMMAND;
            o_command_code                  <= 8'd0;
            length_low_byte                 <= 8'd0;
            message_length                  <= 16'd0;
            payload_bytes_received          <= 16'd0;
            argument_bytes                  <= {8*ARGUMENT_BYTES{1'b0}};
            resync_after_response           <= NO_RESYNC;
            o_response_status               <= `STATUS_OK;
            o_response_payload_length_bytes <= 16'd0;
            silent_cycle_count              <= {SILENCE_COUNTER_WIDTH{1'b0}};
            completion_wait_cycles          <= {COMPLETION_COUNTER_WIDTH{1'b0}};

        end else if (framing_error_aborts_message) begin
            respond(`STATUS_ERR_FRAMING, RESYNC_AFTER_RESPONSE);

        end else if (silence_aborts_message) begin
            respond(`STATUS_ERR_TIMEOUT, NO_RESYNC);

        end else begin
            case (state)
                STATE_WAIT_COMMAND: if (i_rx_byte_valid) begin
                    o_command_code <= i_rx_byte_data;
                    state          <= STATE_RECEIVE_LENGTH_LOW;
                end

                STATE_RECEIVE_LENGTH_LOW: if (i_rx_byte_valid) begin
                    length_low_byte <= i_rx_byte_data;
                    state           <= STATE_RECEIVE_LENGTH_HIGH;
                end

                // Con el encabezado completo se decide como consumir el resto del mensaje
                STATE_RECEIVE_LENGTH_HIGH: if (i_rx_byte_valid) begin
                    message_length         <= declared_length;
                    payload_bytes_received <= 16'd0;

                    if (declared_length > MAX_MESSAGE_LENGTH_BYTES) begin
                        respond(`STATUS_ERR_LEN, RESYNC_AFTER_RESPONSE);
                    end else if (load_can_start) begin
                        o_load_start <= 1'b1;
                        state        <= STATE_FORWARD_LOAD;
                    end else if (declared_length == 16'd0) begin
                        state <= STATE_EXECUTE;
                    end else begin
                        state <= STATE_RECEIVE_PAYLOAD;
                    end
                end

                // Se consume el mensaje completo para no desincronizar el flujo
                STATE_RECEIVE_PAYLOAD: if (i_rx_byte_valid) begin
                    // Con 4 bytes el primero queda en los bits bajos (orden little-endian)
                    if (payload_bytes_received < ARGUMENT_BYTES)
                        argument_bytes <= {i_rx_byte_data, argument_bytes[8*ARGUMENT_BYTES-1:8]};

                    payload_bytes_received <= payload_bytes_after_this_byte;

                    if (payload_bytes_after_this_byte == message_length)
                        state <= STATE_EXECUTE;
                end

                // El program_loader valida y escribe; aca solo se espera su resultado
                STATE_FORWARD_LOAD: if (i_load_finished) begin
                    respond(load_result_status, NO_RESYNC);
                end

                STATE_EXECUTE: begin
                    // Solo llega con LOAD_PROGRAM si la CPU corria al llegar el encabezado
                    if (command_is_load_program) begin
                        respond(`STATUS_ERR_BUSY, NO_RESYNC);
                    end else if (rejection_status != `STATUS_OK) begin
                        respond(rejection_status, NO_RESYNC);
                    end else if (command_is_reset) begin
                        o_reset_request <= 1'b1;
                        state           <= STATE_WAIT_COMPLETION;
                    end else if (command_is_run) begin
                        o_run_request <= 1'b1;
                        state         <= STATE_WAIT_COMPLETION;
                    end else if (command_is_step) begin
                        o_step_request <= 1'b1;
                        state          <= STATE_WAIT_COMPLETION;
                    end else begin
                        respond(`STATUS_OK, NO_RESYNC);   // GET_STATUS y consultas de datos
                    end
                end

                STATE_WAIT_COMPLETION: begin
                    if (i_command_finished)
                        respond(command_result_status, NO_RESYNC);
                    else if (completion_timeout_expired)
                        respond(`STATUS_ERR_INTERNAL, NO_RESYNC);
                end

                STATE_WAIT_RESPONSE_SENT: if (i_response_finished) begin
                    state <= resync_after_response ? STATE_DISCARD_UNTIL_SILENCE
                                                   : STATE_WAIT_COMMAND;
                end

                // Los bytes de un mensaje roto no se interpretan como comandos nuevos
                STATE_DISCARD_UNTIL_SILENCE: if (silence_timeout_expired) begin
                    state <= STATE_WAIT_COMMAND;
                end

                default: respond(`STATUS_ERR_INTERNAL, NO_RESYNC);
            endcase
        end
    end

endmodule
