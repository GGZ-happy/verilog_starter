////////////////////////////////////////////////
//                  WB Stage                  //
////////////////////////////////////////////////

`include "sys_defs.svh"

module stage_wb (
    input EX_WB_PACKET ex2wb_pipe,

    // Memory interface
    input MEM_BLOCK [`BUS_WIDTH-1:0] mem2proc_data,
    input ADDR      [`BUS_WIDTH-1:0] mem2proc_addr,
    input           [`BUS_WIDTH-1:0] mem2proc_valid,

    output COM_PACKET wb2rf_pipe,
    output logic load_complete
);

    // Load complete check
    logic [1:0] block_offset;
    WORD load_data;

    assign block_offset = ex2wb_pipe.result[1][1:0];
    assign load_data = mem2proc_data[0][block_offset];

    assign load_complete = !ex2wb_pipe.valid[1] || ex2wb_pipe.opcode[1] != LC2K_LW
        || (ex2wb_pipe.valid[1] && ex2wb_pipe.opcode[1] == LC2K_LW
        && mem2proc_valid[0] && mem2proc_addr[0] == ex2wb_pipe.ls_addr);

    // Valid
    assign wb2rf_pipe.valid[0] = load_complete && ex2wb_pipe.valid[0];
    assign wb2rf_pipe.valid[1] = load_complete && ex2wb_pipe.valid[1] &&
        (ex2wb_pipe.opcode[1] == LC2K_LW || ex2wb_pipe.opcode[1] == LC2K_SW || 
        !ex2wb_pipe.mispredict[0] || !ex2wb_pipe.valid[0]);
    assign wb2rf_pipe.valid[2] = `FALSE;

    // Write enable and destReg
    assign wb2rf_pipe.wr_en[0] = wb2rf_pipe.valid[0] && ex2wb_pipe.wr_en[0];
    assign wb2rf_pipe.wr_en[1] = wb2rf_pipe.valid[1] && ex2wb_pipe.wr_en[1];
    assign wb2rf_pipe.destReg = ex2wb_pipe.destReg;

    // Write data
    assign wb2rf_pipe.write_data[0] =
        ex2wb_pipe.opcode[0] == LC2K_JALR ? {12'b0, ex2wb_pipe.pc[0] + 1} : ex2wb_pipe.result[0];
    assign wb2rf_pipe.write_data[1] =
        ex2wb_pipe.opcode[1] == LC2K_JALR ? {12'b0, ex2wb_pipe.pc[1] + 1}
        : ex2wb_pipe.opcode[1] == LC2K_LW ? load_data
        : ex2wb_pipe.result[1];

    // Error status
    always_comb begin
        if (ex2wb_pipe.mem_command != MEM_NONE && ex2wb_pipe.result[1][31:20] != '0)
            wb2rf_pipe.error_status = MEM_ACCESS_FAULT;
        else if ((ex2wb_pipe.valid[0] && ex2wb_pipe.opcode[0] > LC2K_NAND)
                || (ex2wb_pipe.valid[1] && ex2wb_pipe.opcode[1] > LC2K_NAND))
            wb2rf_pipe.error_status = ILLEGAL_INST;
        else if (load_complete && ((ex2wb_pipe.valid[0] && ex2wb_pipe.opcode[0] == LC2K_HALT)
                || (ex2wb_pipe.valid[1] && !ex2wb_pipe.mispredict[0]
                && ex2wb_pipe.opcode[1] == LC2K_HALT)))
            wb2rf_pipe.error_status = HALTED;
        else
            wb2rf_pipe.error_status = NO_ERROR;
    end

    // Mispredict output
    always_comb begin
        if (wb2rf_pipe.valid[0] && ex2wb_pipe.mispredict[0]) begin
            wb2rf_pipe.mispredict = `TRUE;
            wb2rf_pipe.next_pc = ex2wb_pipe.branch_target[0];
        end else if (wb2rf_pipe.valid[1] && ex2wb_pipe.mispredict[1]) begin
            wb2rf_pipe.mispredict = `TRUE;
            wb2rf_pipe.next_pc = ex2wb_pipe.branch_target[1];
        end else begin
            wb2rf_pipe.mispredict = `FALSE;
            wb2rf_pipe.next_pc = 'x;
        end
    end

endmodule