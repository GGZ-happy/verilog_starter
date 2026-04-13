//////////////////////////////////////////////////////////////////
//                                                              //
//   Modulename :  stage_com.sv                                 //
//                                                              //
//  Description :  Commit (COM) stage of the pipeline:          //
//                 Update PC, registers, and memory             //
//                                                              //
//////////////////////////////////////////////////////////////////

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

module stage_com (
    input   ID_PACKET id2ex_pipe,

    // Memory inputs and outputs
    input MEM_BLOCK [`BUS_WIDTH-1:0] mem2proc_data,  // Data coming back from memory
    input ADDR      [`BUS_WIDTH-1:0] mem2proc_addr,  // Address of data coming back from memory
    input           [`BUS_WIDTH-1:0] mem2proc_valid, // Indicator that memory is sending data

    output WORD         proc2mem_data,  // Data sent to memory
    output ADDR         ls2mem_addr,    // Address sent to memory
    output MEM_COMMAND  ls2mem_command, // Command sent to memory

    output COM_PACKET wb2rf_pipe
);
    genvar i;

    ////////////////////////////////////////////////
    //                  EX Stage                  //
    ////////////////////////////////////////////////

    logic [1:0] eq;
    logic [1:0] mispredict;
    ADDR  [1:0] branch_target;
    WORD  [1:0] result;
    alu alus [1:0] (
        .opcode(id2ex_pipe.opcode),
        .valA(id2ex_pipe.valA),
        .valB(id2ex_pipe.valB),
        .offset(id2ex_pipe.offset),
        .eq(eq),
        .result(result)
    );

    generate
    for (i = 0; i <= 1; ++i) begin : branch_determine
        assign branch_target[i] = 
            id2ex_pipe.opcode[i] == LC2K_JALR
            ? ((id2ex_pipe.regA[i] == id2ex_pipe.regB[i])
                ? (id2ex_pipe.pc[i] + 1) : id2ex_pipe.valA[i][19:0])
            : (id2ex_pipe.pred_taken[i]
                ? (id2ex_pipe.pc[i] + 1)
                : (id2ex_pipe.pc[i] + id2ex_pipe.offset[i] + 1));
        assign mispredict[i] = id2ex_pipe.valid[i]
            && (id2ex_pipe.opcode[i] == LC2K_JALR
                || (id2ex_pipe.opcode[i] == LC2K_BEQ
                    && (id2ex_pipe.pred_taken[i] != eq[i])));
    end
    endgenerate

    ////////////////////////////////////////////////
    //                 MEM Stage                  //
    ////////////////////////////////////////////////

    logic load_complete;
    WORD load_data;
    logic [1:0] block_offset;

    assign ls2mem_command 
        = (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_LW) ? MEM_LOAD
        : (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_SW) ? MEM_STORE
        : MEM_NONE;
    assign ls2mem_addr[19:2] = result[1][19:2];
    assign ls2mem_addr[1:0] = id2ex_pipe.opcode[1] == LC2K_SW ? result[1][1:0] : '0;
    assign block_offset = result[1][1:0];
    assign load_data = mem2proc_data[0][block_offset];
    assign proc2mem_data = id2ex_pipe.valB[1];

    assign load_complete = !id2ex_pipe.valid[1] || id2ex_pipe.opcode[1] != LC2K_LW
        || (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_LW
        && mem2proc_valid[0] && mem2proc_addr[0] == ls2mem_addr);

    // Don't commit if waiting on load
    // BEQ in slot 0 only invalidates i1 if it's not a memory op
    assign wb2rf_pipe.valid[0] = load_complete && id2ex_pipe.valid[0];
    assign wb2rf_pipe.valid[1] = load_complete && id2ex_pipe.valid[1] && 
        (id2ex_pipe.opcode[1] == LC2K_LW || id2ex_pipe.opcode[1] == LC2K_SW || !mispredict[0]);
    assign wb2rf_pipe.valid[2] = `FALSE;

    always_comb begin
        if (ls2mem_command != MEM_NONE && result[1][31:20] != '0) begin
            wb2rf_pipe.error_status = MEM_ACCESS_FAULT;
        end else if ((id2ex_pipe.valid[0] && id2ex_pipe.opcode[0] > LC2K_NAND)
                || (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] > LC2K_NAND)) begin
            wb2rf_pipe.error_status = ILLEGAL_INST;
        end else if (load_complete && ((id2ex_pipe.valid[0] && id2ex_pipe.opcode[0] == LC2K_HALT)
                || (id2ex_pipe.valid[1] && !mispredict[0] && id2ex_pipe.opcode[1] == LC2K_HALT))) begin
            wb2rf_pipe.error_status = HALTED;
        end else begin
            wb2rf_pipe.error_status = NO_ERROR;
        end
    end

    ////////////////////////////////////////////////
    //                  WB Stage                  //
    ////////////////////////////////////////////////

    generate
    for (i = 0; i <= 1; ++i) begin : write_enable
        assign wb2rf_pipe.wr_en[i] = wb2rf_pipe.valid[i]
            && (id2ex_pipe.opcode[i] == LC2K_ADD
            || id2ex_pipe.opcode[i] == LC2K_NOR
            || id2ex_pipe.opcode[i] == LC2K_LW
            || id2ex_pipe.opcode[i] == LC2K_JALR
            || id2ex_pipe.opcode[i] == LC2K_ADDI
            || id2ex_pipe.opcode[i] == LC2K_NAND);
        assign wb2rf_pipe.destReg[i] = id2ex_pipe.destReg[i];
    end
    endgenerate

    assign wb2rf_pipe.write_data[0] = 
        id2ex_pipe.opcode[0] == LC2K_JALR ? {12'b0, id2ex_pipe.pc[0] + 1}
        : result[0];
    assign wb2rf_pipe.write_data[1] = 
        id2ex_pipe.opcode[1] == LC2K_JALR ? {12'b0, id2ex_pipe.pc[1] + 1}
        : id2ex_pipe.opcode[1] == LC2K_LW ? load_data
        : result[1];

    always_comb begin
        if (wb2rf_pipe.valid[0] && mispredict[0]) begin
            wb2rf_pipe.mispredict = `TRUE;
            wb2rf_pipe.next_pc = branch_target[0];
        end else if (wb2rf_pipe.valid[1] && mispredict[1]) begin
            wb2rf_pipe.mispredict = `TRUE;
            wb2rf_pipe.next_pc = branch_target[1];
        end else begin
            wb2rf_pipe.mispredict = `FALSE;
            wb2rf_pipe.next_pc = 'x;
        end
    end
endmodule // stage_com
