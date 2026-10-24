`timescale 1ns / 1ps

module tb_data_access_checker;

    reg         access_valid;
    reg  [2:0]  funct3;
    reg  [31:0] byte_address;
    wire        is_out_of_range;
    wire        is_misaligned;

    data_access_checker dut (
        .i_access_valid    (access_valid),
        .i_funct3          (funct3),
        .i_byte_address    (byte_address),
        .o_is_out_of_range (is_out_of_range),
        .o_is_misaligned   (is_misaligned)
    );

    integer error_count = 0;
    integer valid_index, funct3_index, address_index;
    reg [31:0] address_list [0:19];

    task check(input valid, input [2:0] size_code, input [31:0] address);
        integer access_size;
        reg expected_out_of_range, expected_misaligned;
        begin
            access_valid = valid;
            funct3       = size_code;
            byte_address = address;
            #1;

            access_size = (size_code == 3'b001 || size_code == 3'b101) ? 2 :
                          (size_code == 3'b010)                        ? 4 : 1;
            expected_out_of_range = valid && (address >= 32'h1000);
            expected_misaligned   = valid && ((address % access_size) != 0);

            if (is_out_of_range !== expected_out_of_range || is_misaligned !== expected_misaligned) begin
                error_count = error_count + 1;
                $display("FALLO: valid=%b funct3=%b addr=%h -> rango=%b/%b alineacion=%b/%b",
                         valid, size_code, address,
                         is_out_of_range, expected_out_of_range, is_misaligned, expected_misaligned);
            end
        end
    endtask

    initial begin
        address_list[0]  = 32'h00000000;  address_list[1]  = 32'h00000001;
        address_list[2]  = 32'h00000002;  address_list[3]  = 32'h00000003;
        address_list[4]  = 32'h00000FFC;  address_list[5]  = 32'h00000FFD;
        address_list[6]  = 32'h00000FFE;  address_list[7]  = 32'h00000FFF;
        address_list[8]  = 32'h00001000;  address_list[9]  = 32'h00001001;
        address_list[10] = 32'h00001003;  address_list[11] = 32'h00001004;
        address_list[12] = 32'h80000000;  address_list[13] = 32'hFFFFF000;
        address_list[14] = 32'hFFFFFFFF;  address_list[15] = 32'h12345678;
        address_list[16] = 32'h00000800;  address_list[17] = 32'h00000801;
        address_list[18] = 32'h00000802;  address_list[19] = 32'h00000804;

        for (valid_index = 0; valid_index < 2; valid_index = valid_index + 1)
            for (funct3_index = 0; funct3_index < 8; funct3_index = funct3_index + 1) begin
                for (address_index = 0; address_index < 20; address_index = address_index + 1)
                    check(valid_index[0], funct3_index[2:0], address_list[address_index]);
                for (address_index = 0; address_index < 200; address_index = address_index + 1)
                    check(valid_index[0], funct3_index[2:0], $urandom);
            end

        if (error_count == 0) $display("TODAS LAS PRUEBAS PASARON");
        else                  $display("HUBO %0d FALLOS", error_count);
        $finish;
    end

endmodule