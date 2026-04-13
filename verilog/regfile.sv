/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  regfile.sv                                          //
//                                                                     //
//  Description :  This module creates the Regfile used by the ID and  //
//                 WB Stages of the Pipeline.                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "../test/ISA.svh"

module regfile (
    input           clock,  // system clock
    input           reset,  // system reset
    input           [1:0] write_en,
    input REG_IDX   [1:0] write_idx,
    input WORD      [1:0] write_data,
    input REG_IDX   [3:0] read_idx,

    output WORD     [3:0] read_out
);

    WORD [15:0] registers; // 16 32-bit Registers

    // Read ports
    integer p; //port
    always_comb begin
        for (p = 0; p < 4; ++p) begin
            // Handle internal forwarding
            unique if (write_en[0] && write_idx[0] == read_idx[p])
                read_out[p] = write_data[0];
            else if (write_en[1] && write_idx[1] == read_idx[p])
                read_out[p] = write_data[1];
            else read_out[p] = registers[read_idx[p]];
        end
    end

    // Write ports
    always_ff @(posedge clock) begin
        if (reset) begin
            registers <= '0;
        end else begin
            if (write_en[0]) registers[write_idx[0]] <= write_data[0];
            if (write_en[1]) registers[write_idx[1]] <= write_data[1];
        end
    end
endmodule // regfile
