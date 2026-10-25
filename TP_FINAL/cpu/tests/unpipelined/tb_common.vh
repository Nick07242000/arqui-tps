// -----------------------------------------------------------------------------
// Infraestructura comun de los testbenches de instrucciones (T2.1.2)
//
// Se incluye DENTRO del modulo de cada testbench. Aporta:
//   - la instancia del datapath bajo prueba (dut) y su reloj
//   - codificadores de instrucciones RV32I (escritos desde la especificacion,
//     sin usar las definiciones del RTL)
//   - tareas para armar un programa, ejecutarlo y comprobar el resultado
//
// Uso tipico de un caso:
//   begin_test("nombre");  emit(...);  emit(HALT_WORD);
//   run_program;           check_register(3, 32'd12);   end_test;
// -----------------------------------------------------------------------------

localparam MAX_RUN_CYCLES  = 5000;
localparam PROGRAM_CAPACITY = 1024;
localparam NAME_BITS       = 8 * 64;

localparam [31:0] HALT_WORD = 32'h0000000B;

// ---- Senales del datapath bajo prueba ---------------------------------------
reg         clk                       = 1'b0;
reg         reset                     = 1'b0;
reg         cpu_en                    = 1'b0;
reg         program_write_enable      = 1'b0;
reg  [9:0]  program_write_word_addr   = 10'd0;
reg  [31:0] program_write_data        = 32'd0;
reg  [4:0]  debug_register_addr       = 5'd0;
reg  [9:0]  debug_data_word_addr      = 10'd0;

wire [31:0] debug_register_data;
wire [31:0] debug_data_word;
wire [31:0] pc;
wire [31:0] instruction;
wire        halted;
wire        instruction_retired;
wire        illegal_instruction;
wire        data_out_of_range;
wire        data_misaligned;

unpipelined_datapath dut (
    .i_clk                     (clk),
    .i_reset                   (reset),
    .i_cpu_en                  (cpu_en),
    .i_program_write_enable    (program_write_enable),
    .i_program_write_word_addr (program_write_word_addr),
    .i_program_write_data      (program_write_data),
    .i_debug_register_addr     (debug_register_addr),
    .o_debug_register_data     (debug_register_data),
    .i_debug_data_word_addr    (debug_data_word_addr),
    .o_debug_data_word         (debug_data_word),
    .o_pc                      (pc),
    .o_instruction             (instruction),
    .o_halted                  (halted),
    .o_instruction_retired     (instruction_retired),
    .o_illegal_instruction     (illegal_instruction),
    .o_data_out_of_range       (data_out_of_range),
    .o_data_misaligned         (data_misaligned)
);

always #5 clk = ~clk;

// ---- Codificadores de instrucciones -------------------------------------------
function [31:0] encode_r_type(input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
                              input [2:0] funct3, input [4:0] rd);
    encode_r_type = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
endfunction

function [31:0] encode_i_type(input [11:0] imm, input [4:0] rs1, input [2:0] funct3,
                              input [4:0] rd, input [6:0] opcode);
    encode_i_type = {imm, rs1, funct3, rd, opcode};
endfunction

function [31:0] encode_s_type(input [11:0] imm, input [4:0] rs2, input [4:0] rs1,
                              input [2:0] funct3);
    encode_s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
endfunction

function [31:0] encode_b_type(input [12:0] offset, input [4:0] rs2, input [4:0] rs1,
                              input [2:0] funct3);
    encode_b_type = {offset[12], offset[10:5], rs2, rs1, funct3,
                     offset[4:1], offset[11], 7'b1100011};
endfunction

function [31:0] encode_j_type(input [20:0] offset, input [4:0] rd);
    encode_j_type = {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
endfunction

// ---- Instrucciones R: operaciones entre registros -------------------------
function [31:0] instr_add (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_add  = encode_r_type(7'b0000000, rs2, rs1, 3'b000, rd);
endfunction
function [31:0] instr_sub (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_sub  = encode_r_type(7'b0100000, rs2, rs1, 3'b000, rd);
endfunction
function [31:0] instr_sll (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_sll  = encode_r_type(7'b0000000, rs2, rs1, 3'b001, rd);
endfunction
function [31:0] instr_slt (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_slt  = encode_r_type(7'b0000000, rs2, rs1, 3'b010, rd);
endfunction
function [31:0] instr_sltu(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_sltu = encode_r_type(7'b0000000, rs2, rs1, 3'b011, rd);
endfunction
function [31:0] instr_xor (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_xor  = encode_r_type(7'b0000000, rs2, rs1, 3'b100, rd);
endfunction
function [31:0] instr_srl (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_srl  = encode_r_type(7'b0000000, rs2, rs1, 3'b101, rd);
endfunction
function [31:0] instr_sra (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_sra  = encode_r_type(7'b0100000, rs2, rs1, 3'b101, rd);
endfunction
function [31:0] instr_or  (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_or   = encode_r_type(7'b0000000, rs2, rs1, 3'b110, rd);
endfunction
function [31:0] instr_and (input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
    instr_and  = encode_r_type(7'b0000000, rs2, rs1, 3'b111, rd);
endfunction

// ---- Instrucciones I: operaciones con inmediato -----------------------------
function [31:0] instr_addi (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_addi  = encode_i_type(imm, rs1, 3'b000, rd, 7'b0010011);
endfunction
function [31:0] instr_slti (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_slti  = encode_i_type(imm, rs1, 3'b010, rd, 7'b0010011);
endfunction
function [31:0] instr_sltiu(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_sltiu = encode_i_type(imm, rs1, 3'b011, rd, 7'b0010011);
endfunction
function [31:0] instr_xori (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_xori  = encode_i_type(imm, rs1, 3'b100, rd, 7'b0010011);
endfunction
function [31:0] instr_ori  (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_ori   = encode_i_type(imm, rs1, 3'b110, rd, 7'b0010011);
endfunction
function [31:0] instr_andi (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_andi  = encode_i_type(imm, rs1, 3'b111, rd, 7'b0010011);
endfunction
function [31:0] instr_slli (input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
    instr_slli  = encode_i_type({7'b0000000, shamt}, rs1, 3'b001, rd, 7'b0010011);
endfunction
function [31:0] instr_srli (input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
    instr_srli  = encode_i_type({7'b0000000, shamt}, rs1, 3'b101, rd, 7'b0010011);
endfunction
function [31:0] instr_srai (input [4:0] rd, input [4:0] rs1, input [4:0] shamt);
    instr_srai  = encode_i_type({7'b0100000, shamt}, rs1, 3'b101, rd, 7'b0010011);
endfunction

// ---- Loads (rd, base, desplazamiento) ---------------------------------------
function [31:0] instr_lb (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_lb  = encode_i_type(imm, rs1, 3'b000, rd, 7'b0000011);
endfunction
function [31:0] instr_lh (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_lh  = encode_i_type(imm, rs1, 3'b001, rd, 7'b0000011);
endfunction
function [31:0] instr_lw (input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_lw  = encode_i_type(imm, rs1, 3'b010, rd, 7'b0000011);
endfunction
function [31:0] instr_lbu(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_lbu = encode_i_type(imm, rs1, 3'b100, rd, 7'b0000011);
endfunction
function [31:0] instr_lhu(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_lhu = encode_i_type(imm, rs1, 3'b101, rd, 7'b0000011);
endfunction

// ---- Stores (dato, base, desplazamiento) ------------------------------------
function [31:0] instr_sb(input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
    instr_sb = encode_s_type(imm, rs2, rs1, 3'b000);
endfunction
function [31:0] instr_sh(input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
    instr_sh = encode_s_type(imm, rs2, rs1, 3'b001);
endfunction
function [31:0] instr_sw(input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
    instr_sw = encode_s_type(imm, rs2, rs1, 3'b010);
endfunction

// ---- Saltos y lui -----------------------------------------------------------
function [31:0] instr_beq(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    instr_beq = encode_b_type(offset, rs2, rs1, 3'b000);
endfunction
function [31:0] instr_bne(input [4:0] rs1, input [4:0] rs2, input [12:0] offset);
    instr_bne = encode_b_type(offset, rs2, rs1, 3'b001);
endfunction
function [31:0] instr_jal(input [4:0] rd, input [20:0] offset);
    instr_jal = encode_j_type(offset, rd);
endfunction
function [31:0] instr_jalr(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
    instr_jalr = encode_i_type(imm, rs1, 3'b000, rd, 7'b1100111);
endfunction
function [31:0] instr_lui(input [4:0] rd, input [19:0] imm20);
    instr_lui = {imm20, rd, 7'b0110111};
endfunction

// ---- Contadores de resultados -------------------------------------------------
integer cases_total  = 0;
integer cases_failed = 0;
integer case_errors  = 0;
reg [NAME_BITS-1:0] current_test_name;

// ---- Armado del programa ----------------------------------------------------
reg [31:0] program_words [0:PROGRAM_CAPACITY-1];
integer    program_length;

task emit(input [31:0] instruction_word);
    begin
        program_words[program_length] = instruction_word;
        program_length = program_length + 1;
    end
endtask

task emit_nops(input integer count);
    integer nop_index;
    begin
        for (nop_index = 0; nop_index < count; nop_index = nop_index + 1)
            emit(instr_addi(0, 0, 0));
    end
endtask

// Carga un valor de 32 bits en un registro con lui + addi (siempre 2 palabras)
task emit_load_immediate(input [4:0] rd, input [31:0] value);
    reg [31:0] upper_bits;
    begin
        upper_bits = (value + 32'h0000_0800) >> 12;   // compensa el signo de addi
        emit(instr_lui(rd, upper_bits[19:0]));
        emit(instr_addi(rd, rd, value[11:0]));
    end
endtask

// ---- Ejecucion --------------------------------------------------------------
integer last_run_cycles;
integer last_retired_count;
reg     seen_illegal;
reg     seen_out_of_range;
reg     seen_misaligned;

// Carga el programa, aplica reset (despues de cargar) y ejecuta hasta HALT.
// last_run_cycles cuenta los ciclos habilitados antes de llegar a HALT.
task run_program;
    integer word_index;
    reg     run_finished;
    begin
        for (word_index = 0; word_index < program_length; word_index = word_index + 1) begin
            @(negedge clk);
            program_write_enable    = 1'b1;
            program_write_word_addr = word_index;
            program_write_data      = program_words[word_index];
        end
        @(negedge clk);
        program_write_enable = 1'b0;

        reset = 1'b1;
        @(negedge clk);
        @(negedge clk);
        reset = 1'b0;

        last_run_cycles    = 0;
        last_retired_count = 0;
        seen_illegal       = 1'b0;
        seen_out_of_range  = 1'b0;
        seen_misaligned    = 1'b0;
        run_finished       = 1'b0;
        cpu_en             = 1'b1;

        while (!run_finished) begin
            @(posedge clk);
            if (halted) begin
                run_finished = 1'b1;
            end else if (last_run_cycles >= MAX_RUN_CYCLES) begin
                case_errors  = case_errors + 1;
                run_finished = 1'b1;
                $display("  [FAIL] %0s: no llego a HALT en %0d ciclos (pc = 0x%08h)",
                         current_test_name, MAX_RUN_CYCLES, pc);
            end else begin
                last_run_cycles = last_run_cycles + 1;
                if (instruction_retired) last_retired_count = last_retired_count + 1;
                if (illegal_instruction) seen_illegal      = 1'b1;
                if (data_out_of_range)   seen_out_of_range = 1'b1;
                if (data_misaligned)     seen_misaligned   = 1'b1;
            end
        end

        @(negedge clk);
        cpu_en = 1'b0;
    end
endtask

// ---- Comprobaciones ---------------------------------------------------------

task begin_test(input [NAME_BITS-1:0] test_name);
    begin
        current_test_name = test_name;
        case_errors       = 0;
        program_length    = 0;
    end
endtask

task end_test;
    begin
        cases_total = cases_total + 1;
        if (case_errors == 0) begin
            $display("[PASS] %0s", current_test_name);
        end else begin
            cases_failed = cases_failed + 1;
        end
    end
endtask

task check_register(input [4:0] register_index, input [31:0] expected);
    reg [31:0] actual;
    begin
        debug_register_addr = register_index;
        #1 actual = debug_register_data;
        if (actual !== expected) begin
            case_errors = case_errors + 1;
            $display("  [FAIL] %0s: x%0d = 0x%08h, esperado 0x%08h",
                     current_test_name, register_index, actual, expected);
        end
    end
endtask

task check_memory_word(input [9:0] word_index, input [31:0] expected);
    reg [31:0] actual;
    begin
        debug_data_word_addr = word_index;
        @(posedge clk);
        #1 actual = debug_data_word;
        if (actual !== expected) begin
            case_errors = case_errors + 1;
            $display("  [FAIL] %0s: dmem[%0d] = 0x%08h, esperado 0x%08h",
                     current_test_name, word_index, actual, expected);
        end
    end
endtask

task check_pc(input [31:0] expected);
    begin
        if (pc !== expected) begin
            case_errors = case_errors + 1;
            $display("  [FAIL] %0s: pc final = 0x%08h, esperado 0x%08h",
                     current_test_name, pc, expected);
        end
    end
endtask

task check_run_stats(input integer expected_retired, input integer expected_cycles);
    begin
        if (last_retired_count !== expected_retired || last_run_cycles !== expected_cycles) begin
            case_errors = case_errors + 1;
            $display("  [FAIL] %0s: instrucciones/ciclos = %0d/%0d, esperado %0d/%0d",
                     current_test_name, last_retired_count, last_run_cycles,
                     expected_retired, expected_cycles);
        end
    end
endtask

task check_flags(input expected_illegal, input expected_out_of_range, input expected_misaligned);
    begin
        if (seen_illegal !== expected_illegal ||
            seen_out_of_range !== expected_out_of_range ||
            seen_misaligned !== expected_misaligned) begin
            case_errors = case_errors + 1;
            $display("  [FAIL] %0s: flags ilegal/fuera_de_rango/desalineado = %b/%b/%b, esperado %b/%b/%b",
                     current_test_name, seen_illegal, seen_out_of_range, seen_misaligned,
                     expected_illegal, expected_out_of_range, expected_misaligned);
        end
    end
endtask

task finish_suite(input [NAME_BITS-1:0] suite_name);
    begin
        $display("----------------------------------------------------------------");
        if (cases_failed == 0)
            $display("%0s: %0d casos, TODOS OK", suite_name, cases_total);
        else
            $display("%0s: %0d casos, %0d FALLARON", suite_name, cases_total, cases_failed);
        $finish;
    end
endtask
