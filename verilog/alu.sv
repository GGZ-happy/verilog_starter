`include "sys_defs.svh"

// This module is purely combinational
module alu (
    input LC2K_OPCODE opcode,
    input WORD        valA,
    input WORD        valB,
    input ADDR        offset,
    output logic      eq,
    output WORD       result
);

    assign eq = valA == valB;
    always_comb begin
        case (opcode)
            LC2K_ADD:   result = valA + valB;
            LC2K_NOR:   result = ~(valA | valB);
            LC2K_NAND:  result = ~(valA & valB);
            default:    result = valA + signed'(offset);
        endcase
    end
endmodule // alu