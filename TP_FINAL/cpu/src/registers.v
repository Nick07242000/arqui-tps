// -----------------------------------------------------------------------------
// Banco de registros RISC-V: 32 registros de 32 bits.
// -----------------------------------------------------------------------------

module register_file #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 5,
    parameter REG_COUNT  = 32
) (
    input  wire                    i_clk,
    input  wire                    i_reset,            // reset sincrono (cpu_rst)
    input  wire                    i_cpu_en,           // habilita el avance del CPU

    // Puertos de lectura (etapa ID)
    input  wire [ADDR_WIDTH-1:0]   i_read_addr_a,
    input  wire [ADDR_WIDTH-1:0]   i_read_addr_b,
    output wire [DATA_WIDTH-1:0]   o_read_data_a,
    output wire [DATA_WIDTH-1:0]   o_read_data_b,

    // Puerto de escritura (etapa WB)
    input  wire                    i_write_enable,
    input  wire [ADDR_WIDTH-1:0]   i_write_addr,
    input  wire [DATA_WIDTH-1:0]   i_write_data,

    // Puerto de debug (solo lectura, no usa bypass)
    input  wire [ADDR_WIDTH-1:0]   i_debug_read_addr,
    output wire [DATA_WIDTH-1:0]   o_debug_read_data
);

    // -------------------------------------------------------------------------
    // Almacenamiento y senales internas
    // -------------------------------------------------------------------------
    localparam [ADDR_WIDTH-1:0] ZERO_REG_ADDR = {ADDR_WIDTH{1'b0}};

    reg [DATA_WIDTH-1:0] registers [0:REG_COUNT-1];

    // La escritura es efectiva solo si el CPU avanza y el destino no es x0
    wire write_is_effective = i_cpu_en
                            && i_write_enable
                            && (i_write_addr != ZERO_REG_ADDR);

    // -------------------------------------------------------------------------
    // Escritura sincrona y reset
    // -------------------------------------------------------------------------
    integer reg_index;

    always @(posedge i_clk) begin
        if (i_reset) begin
            for (reg_index = 0; reg_index < REG_COUNT; reg_index = reg_index + 1)
                registers[reg_index] <= {DATA_WIDTH{1'b0}};
        end else if (write_is_effective) begin
            registers[i_write_addr] <= i_write_data;
        end
    end

    // -------------------------------------------------------------------------
    // Lectura combinacional con bypass WB -> ID
    // -------------------------------------------------------------------------
    wire read_a_is_zero_reg = (i_read_addr_a == ZERO_REG_ADDR);
    wire read_b_is_zero_reg = (i_read_addr_b == ZERO_REG_ADDR);

    wire bypass_a = write_is_effective && (i_write_addr == i_read_addr_a);
    wire bypass_b = write_is_effective && (i_write_addr == i_read_addr_b);

    assign o_read_data_a = read_a_is_zero_reg ? {DATA_WIDTH{1'b0}} :
                           bypass_a           ? i_write_data       :
                                                registers[i_read_addr_a];

    assign o_read_data_b = read_b_is_zero_reg ? {DATA_WIDTH{1'b0}} :
                           bypass_b           ? i_write_data       :
                                                registers[i_read_addr_b];

    // -------------------------------------------------------------------------
    // Lectura de debug: valor almacenado, sin bypass
    // -------------------------------------------------------------------------
    assign o_debug_read_data = (i_debug_read_addr == ZERO_REG_ADDR)
                             ? {DATA_WIDTH{1'b0}}
                             : registers[i_debug_read_addr];

endmodule
