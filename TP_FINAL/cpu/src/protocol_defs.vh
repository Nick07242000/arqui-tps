// -----------------------------------------------------------------------------
// Constantes del protocolo UART de la Debug Unit
//   Request : [CMD:1][LEN:2 LE][PAYLOAD:LEN]
//   Response: [STATUS:1][LEN:2 LE][PAYLOAD:LEN]
// -----------------------------------------------------------------------------
`ifndef PROTOCOL_DEFS_VH
`define PROTOCOL_DEFS_VH

// ---- Codigos de comando (byte CMD del request) ------------------------------
`define COMMAND_LOAD_PROGRAM  8'h01
`define COMMAND_RESET         8'h02
`define COMMAND_RUN           8'h03
`define COMMAND_STEP          8'h04
`define COMMAND_GET_STATUS    8'h05
`define COMMAND_GET_REGS      8'h06
`define COMMAND_GET_PIPELINE  8'h07
`define COMMAND_GET_MEMORY    8'h08

// ---- Codigos de STATUS (primer byte de la respuesta) ------------------------
`define STATUS_OK              8'h00
`define STATUS_ERR_CMD         8'h01   // comando desconocido
`define STATUS_ERR_LEN         8'h02   // LEN incompatible con el comando o mayor que el maximo
`define STATUS_ERR_ARG         8'h03   // argumento fuera de rango
`define STATUS_ERR_STATE       8'h04   // comando no valido en el estado actual
`define STATUS_ERR_BUSY        8'h05   // la CPU esta en RUNNING
`define STATUS_ERR_NO_PROGRAM  8'h06   // RUN o STEP sin programa valido
`define STATUS_ERR_TIMEOUT     8'h07   // mensaje incompleto
`define STATUS_ERR_FRAMING     8'h08   // error de framing en la UART
`define STATUS_ERR_INTERNAL    8'h09   // el sistema no respondio como se esperaba

// ---- Largo del payload de las respuestas OK ---------------------------------
`define PAYLOAD_LENGTH_STATE_BYTES     16'd1     // LOAD_PROGRAM, RESET, RUN, STEP: state
`define PAYLOAD_LENGTH_STATUS_BYTES    16'd17    // GET_STATUS
`define PAYLOAD_LENGTH_REGS_BYTES      16'd128   // GET_REGS: x0..x31
`define PAYLOAD_LENGTH_PIPELINE_BYTES  16'd73    // GET_PIPELINE: IF/ID + ID/EX + EX/MEM + MEM/WB

`endif
