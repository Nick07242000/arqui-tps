`timescale 1ns / 1ps
`include "alu_ops.vh"
`include "riscv_defs.vh"

module tb_control_unit;

    reg  [31:0] i_instruction;

    wire [3:0]  o_alu_op;
    wire [2:0]  o_imm_type;
    wire        o_alu_src_b_is_imm, o_reg_write, o_mem_read, o_mem_write;
    wire        o_is_branch, o_is_jal, o_is_jalr, o_is_halt, o_is_illegal;
    wire        o_uses_rs1, o_uses_rs2;

    integer error_count = 0;

    control_unit dut (
        .i_instruction      (i_instruction),
        .o_alu_op           (o_alu_op),
        .o_alu_src_b_is_imm (o_alu_src_b_is_imm),
        .o_imm_type         (o_imm_type),
        .o_reg_write        (o_reg_write),
        .o_mem_read         (o_mem_read),
        .o_mem_write        (o_mem_write),
        .o_is_branch        (o_is_branch),
        .o_is_jal           (o_is_jal),
        .o_is_jalr          (o_is_jalr),
        .o_is_halt          (o_is_halt),
        .o_is_illegal       (o_is_illegal),
        .o_uses_rs1         (o_uses_rs1),
        .o_uses_rs2         (o_uses_rs2)
    );

    // -------------------------------------------------------------------------
    // Banderas de control (una por bit, en el orden de observed_flags)
    // -------------------------------------------------------------------------
    localparam [10:0] FLAG_SRC_B_IMM = 11'b000_0000_0001;
    localparam [10:0] FLAG_REG_WRITE = 11'b000_0000_0010;
    localparam [10:0] FLAG_MEM_READ  = 11'b000_0000_0100;
    localparam [10:0] FLAG_MEM_WRITE = 11'b000_0000_1000;
    localparam [10:0] FLAG_BRANCH    = 11'b000_0001_0000;
    localparam [10:0] FLAG_JAL       = 11'b000_0010_0000;
    localparam [10:0] FLAG_JALR      = 11'b000_0100_0000;
    localparam [10:0] FLAG_HALT      = 11'b000_1000_0000;
    localparam [10:0] FLAG_ILLEGAL   = 11'b001_0000_0000;
    localparam [10:0] FLAG_USES_RS1  = 11'b010_0000_0000;
    localparam [10:0] FLAG_USES_RS2  = 11'b100_0000_0000;
    localparam [10:0] FLAGS_NONE     = 11'b000_0000_0000;

    wire [10:0] observed_flags = {o_uses_rs2, o_uses_rs1, o_is_illegal, o_is_halt,
                                  o_is_jalr, o_is_jal, o_is_branch, o_mem_write,
                                  o_mem_read, o_reg_write, o_alu_src_b_is_imm};

    // Registros usados en las instrucciones de prueba
    localparam [4:0] RS1 = 5'd10;
    localparam [4:0] RS2 = 5'd11;
    localparam [4:0] RD  = 5'd12;

    // -------------------------------------------------------------------------
    // Funciones de codificacion por formato
    // -------------------------------------------------------------------------
    function [31:0] encode_r(input [6:0] funct7, input [2:0] funct3);
        encode_r = {funct7, RS2, RS1, funct3, RD, `OPCODE_R_TYPE};
    endfunction

    function [31:0] encode_i(input [11:0] imm, input [2:0] funct3, input [6:0] opcode);
        encode_i = {imm, RS1, funct3, RD, opcode};
    endfunction

    function [31:0] encode_s(input [11:0] imm, input [2:0] funct3);
        encode_s = {imm[11:5], RS2, RS1, funct3, imm[4:0], `OPCODE_STORE};
    endfunction

    function [31:0] encode_b(input [12:0] imm, input [2:0] funct3);
        encode_b = {imm[12], imm[10:5], RS2, RS1, funct3, imm[4:1], imm[11], `OPCODE_BRANCH};
    endfunction

    function [31:0] encode_u(input [19:0] imm);
        encode_u = {imm, RD, `OPCODE_LUI};
    endfunction

    function [31:0] encode_j(input [20:0] imm);
        encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], RD, `OPCODE_JAL};
    endfunction

    // -------------------------------------------------------------------------
    // Verificacion de una instruccion
    // -------------------------------------------------------------------------
    task check(
        input [8*16-1:0] test_name,
        input [31:0]     instruction,
        input [3:0]      expected_alu_op,
        input [2:0]      expected_imm_type,
        input [10:0]     expected_flags
    );
    begin
        i_instruction = instruction;
        #1;
        if (o_alu_op     !== expected_alu_op   ||
            o_imm_type   !== expected_imm_type ||
            observed_flags !== expected_flags) begin
            error_count = error_count + 1;
            $display("FALLO %0s: instr=%h", test_name, instruction);
            $display("  alu_op=%b (esp %b)  imm_type=%b (esp %b)  flags=%b (esp %b)",
                     o_alu_op, expected_alu_op, o_imm_type, expected_imm_type,
                     observed_flags, expected_flags);
        end
    end
    endtask

    // Combinaciones de banderas frecuentes
    localparam [10:0] FLAGS_R_TYPE = FLAG_REG_WRITE | FLAG_USES_RS1 | FLAG_USES_RS2;
    localparam [10:0] FLAGS_OP_IMM = FLAG_REG_WRITE | FLAG_USES_RS1 | FLAG_SRC_B_IMM;
    localparam [10:0] FLAGS_LOAD   = FLAGS_OP_IMM   | FLAG_MEM_READ;
    localparam [10:0] FLAGS_STORE  = FLAG_MEM_WRITE | FLAG_USES_RS1 | FLAG_USES_RS2 | FLAG_SRC_B_IMM;
    localparam [10:0] FLAGS_BRANCH = FLAG_BRANCH    | FLAG_USES_RS1 | FLAG_USES_RS2;

    initial begin
        // ---- Tipo R ---------------------------------------------------------
        check("add",   encode_r(`FUNCT7_BASE, `FUNCT3_ADD_SUB), `ALU_OP_ADD,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("sub",   encode_r(`FUNCT7_ALT,  `FUNCT3_ADD_SUB), `ALU_OP_SUB,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("sll",   encode_r(`FUNCT7_BASE, `FUNCT3_SLL),     `ALU_OP_SLL,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("slt",   encode_r(`FUNCT7_BASE, `FUNCT3_SLT),     `ALU_OP_SLT,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("sltu",  encode_r(`FUNCT7_BASE, `FUNCT3_SLTU),    `ALU_OP_SLTU, `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("xor",   encode_r(`FUNCT7_BASE, `FUNCT3_XOR),     `ALU_OP_XOR,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("srl",   encode_r(`FUNCT7_BASE, `FUNCT3_SRL_SRA), `ALU_OP_SRL,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("sra",   encode_r(`FUNCT7_ALT,  `FUNCT3_SRL_SRA), `ALU_OP_SRA,  `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("or",    encode_r(`FUNCT7_BASE, `FUNCT3_OR),      `ALU_OP_OR,   `IMM_TYPE_NONE, FLAGS_R_TYPE);
        check("and",   encode_r(`FUNCT7_BASE, `FUNCT3_AND),     `ALU_OP_AND,  `IMM_TYPE_NONE, FLAGS_R_TYPE);

        // ---- Tipo I: aritmeticas/logicas ------------------------------------
        check("addi",       encode_i(12'd5,   `FUNCT3_ADD_SUB, `OPCODE_OP_IMM), `ALU_OP_ADD,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("addi neg",   encode_i(12'hFFF, `FUNCT3_ADD_SUB, `OPCODE_OP_IMM), `ALU_OP_ADD,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("addi bit30", encode_i(12'h400, `FUNCT3_ADD_SUB, `OPCODE_OP_IMM), `ALU_OP_ADD,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("slti",       encode_i(12'd5,   `FUNCT3_SLT,     `OPCODE_OP_IMM), `ALU_OP_SLT,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("sltiu",      encode_i(12'd5,   `FUNCT3_SLTU,    `OPCODE_OP_IMM), `ALU_OP_SLTU, `IMM_TYPE_I, FLAGS_OP_IMM);
        check("xori",       encode_i(12'd5,   `FUNCT3_XOR,     `OPCODE_OP_IMM), `ALU_OP_XOR,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("ori",        encode_i(12'd5,   `FUNCT3_OR,      `OPCODE_OP_IMM), `ALU_OP_OR,   `IMM_TYPE_I, FLAGS_OP_IMM);
        check("andi",       encode_i(12'd5,   `FUNCT3_AND,     `OPCODE_OP_IMM), `ALU_OP_AND,  `IMM_TYPE_I, FLAGS_OP_IMM);
        check("slli",       encode_i({`FUNCT7_BASE, 5'd3}, `FUNCT3_SLL,     `OPCODE_OP_IMM), `ALU_OP_SLL, `IMM_TYPE_I, FLAGS_OP_IMM);
        check("srli",       encode_i({`FUNCT7_BASE, 5'd3}, `FUNCT3_SRL_SRA, `OPCODE_OP_IMM), `ALU_OP_SRL, `IMM_TYPE_I, FLAGS_OP_IMM);
        check("srai",       encode_i({`FUNCT7_ALT,  5'd3}, `FUNCT3_SRL_SRA, `OPCODE_OP_IMM), `ALU_OP_SRA, `IMM_TYPE_I, FLAGS_OP_IMM);

        // ---- Tipo I: loads --------------------------------------------------
        check("lb",   encode_i(12'd8, `FUNCT3_BYTE,   `OPCODE_LOAD), `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);
        check("lh",   encode_i(12'd8, `FUNCT3_HALF,   `OPCODE_LOAD), `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);
        check("lw",   encode_i(12'd8, `FUNCT3_WORD,   `OPCODE_LOAD), `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);
        check("lbu",  encode_i(12'd8, `FUNCT3_BYTE_U, `OPCODE_LOAD), `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);
        check("lhu",  encode_i(12'd8, `FUNCT3_HALF_U, `OPCODE_LOAD), `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);

        // ---- Tipo S ---------------------------------------------------------
        check("sb",   encode_s(12'd8, `FUNCT3_BYTE), `ALU_OP_ADD, `IMM_TYPE_S, FLAGS_STORE);
        check("sh",   encode_s(12'd8, `FUNCT3_HALF), `ALU_OP_ADD, `IMM_TYPE_S, FLAGS_STORE);
        check("sw",   encode_s(12'd8, `FUNCT3_WORD), `ALU_OP_ADD, `IMM_TYPE_S, FLAGS_STORE);

        // ---- Tipo B ---------------------------------------------------------
        check("beq",  encode_b(13'd8, `FUNCT3_BEQ), `ALU_OP_ADD, `IMM_TYPE_B, FLAGS_BRANCH);
        check("bne",  encode_b(13'd8, `FUNCT3_BNE), `ALU_OP_ADD, `IMM_TYPE_B, FLAGS_BRANCH);

        // ---- Saltos, lui y HALT ---------------------------------------------
        check("jal",  encode_j(21'd8), `ALU_OP_ADD, `IMM_TYPE_J,
              FLAG_JAL | FLAG_REG_WRITE);
        check("jalr", encode_i(12'd4, `FUNCT3_JALR, `OPCODE_JALR), `ALU_OP_ADD, `IMM_TYPE_I,
              FLAG_JALR | FLAG_REG_WRITE | FLAG_USES_RS1 | FLAG_SRC_B_IMM);
        check("lui",  encode_u(20'h12345), `ALU_OP_PASS_B, `IMM_TYPE_U,
              FLAG_REG_WRITE | FLAG_SRC_B_IMM);
        check("halt", `HALT_INSTRUCTION, `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_HALT);

        // ---- Palabras conocidas (referencia externa) ------------------------
        check("addi x1,x0,5", 32'h00500093, `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_OP_IMM);
        check("lw x2,8(x1)",  32'h0080A103, `ALU_OP_ADD, `IMM_TYPE_I, FLAGS_LOAD);
        check("beq x1,x2,8",  32'h00208463, `ALU_OP_ADD, `IMM_TYPE_B, FLAGS_BRANCH);

        // ---- Ilegales: solo FLAG_ILLEGAL, sin ningun efecto -----------------
        check("palabra cero", 32'h00000000, `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("todo unos",    32'hFFFFFFFF, `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("ld",           encode_i(12'd8, 3'b011, `OPCODE_LOAD),  `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("lwu",          encode_i(12'd8, 3'b110, `OPCODE_LOAD),  `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("sd",           encode_s(12'd8, 3'b011),                `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("blt",          encode_b(13'd8, 3'b100),                `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("mul (funct7)", encode_r(7'b0000001, `FUNCT3_ADD_SUB),  `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("sll alt",      encode_r(`FUNCT7_ALT, `FUNCT3_SLL),     `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("slli alt",     encode_i({`FUNCT7_ALT, 5'd3}, `FUNCT3_SLL, `OPCODE_OP_IMM), `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("srli shamt5",  encode_i({7'b0000001, 5'd3}, `FUNCT3_SRL_SRA, `OPCODE_OP_IMM), `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("jalr f3=1",    encode_i(12'd4, 3'b001, `OPCODE_JALR),  `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("auipc",        {20'h12345, RD, 7'b0010111},            `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);
        check("custom-0 rd",  32'h0000008B,                           `ALU_OP_ADD, `IMM_TYPE_NONE, FLAG_ILLEGAL);

        if (error_count == 0) $display("tb_control_unit: TODAS LAS PRUEBAS PASARON");
        else                  $display("tb_control_unit: %0d FALLOS", error_count);
        $finish;
    end

endmodule
