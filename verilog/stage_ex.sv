////////////////////////////////////////////////
//                  EX Stage                  //
////////////////////////////////////////////////
    
`include "sys_defs.svh"

module stage_ex (
    input ID_PACKET id2ex_pipe,
    input EX_WB_PACKET ex2wb_pipe,
    output EX_WB_PACKET ex_wb_out
);
    genvar i;

    // forwarding mux
    WORD [1:0] fwd_valA, fwd_valB;
    
    generate
    for (i = 0; i <= 1; ++i) begin : forwarding
        always_comb begin
            if (ex2wb_pipe.wr_en[0] && ex2wb_pipe.destReg[0] == id2ex_pipe.regA[i])
                fwd_valA[i] = ex2wb_pipe.result[0];
            else if (ex2wb_pipe.wr_en[1] && ex2wb_pipe.destReg[1] == id2ex_pipe.regA[i])
                fwd_valA[i] = ex2wb_pipe.result[1];
            else
                fwd_valA[i] = id2ex_pipe.valA[i];

            if (ex2wb_pipe.wr_en[0] && ex2wb_pipe.destReg[0] == id2ex_pipe.regB[i])
                fwd_valB[i] = ex2wb_pipe.result[0];
            else if (ex2wb_pipe.wr_en[1] && ex2wb_pipe.destReg[1] == id2ex_pipe.regB[i])
                fwd_valB[i] = ex2wb_pipe.result[1];
            else
                fwd_valB[i] = id2ex_pipe.valB[i];
        end
    end
    endgenerate
        
    
    // ALU
    logic [1:0] eq;
    logic [1:0] mispredict;
    ADDR  [1:0] branch_target;
    WORD  [1:0] result;
    alu alus [1:0] (
        .opcode(id2ex_pipe.opcode),
        .valA(fwd_valA),
        .valB(fwd_valB),
        .offset(id2ex_pipe.offset),
        .eq(eq),
        .result(result)
    );

    // Branch
    generate
    for (i = 0; i <= 1; ++i) begin : branch_determine
        assign branch_target[i] = 
            id2ex_pipe.opcode[i] == LC2K_JALR
            ? ((id2ex_pipe.regA[i] == id2ex_pipe.regB[i])
                ? (id2ex_pipe.pc[i] + 1) : fwd_valA[i][19:0]) // JALR
            : (id2ex_pipe.pred_taken[i]
                ? (id2ex_pipe.pc[i] + 1)
                : (id2ex_pipe.pc[i] + id2ex_pipe.offset[i] + 1)); // BEQ
        assign mispredict[i] = id2ex_pipe.valid[i]
            && (id2ex_pipe.opcode[i] == LC2K_JALR // didn't predict JALR
                || (id2ex_pipe.opcode[i] == LC2K_BEQ
                    && (id2ex_pipe.pred_taken[i] != eq[i]))); // beq but predict wrong
    end
    endgenerate

    ////////////////////////////////////////////////
    //                 MEM Stage                  //
    ////////////////////////////////////////////////

    assign ex_wb_out.mem_command
        = (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_LW) ? MEM_LOAD
        : (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_SW) ? MEM_STORE
        : MEM_NONE;
    assign ex_wb_out.ls_addr[19:2] = result[1][19:2];
    assign ex_wb_out.ls_addr[1:0] = id2ex_pipe.opcode[1] == LC2K_SW ? result[1][1:0] : '0;
    assign ex_wb_out.store_data = fwd_valB[1];

    // write enable
    generate
    for (i = 0; i <= 1; ++i) begin : write_enable
        assign ex_wb_out.wr_en[i] = id2ex_pipe.valid[i]
            && (id2ex_pipe.opcode[i] == LC2K_ADD
            || id2ex_pipe.opcode[i] == LC2K_NOR
            || id2ex_pipe.opcode[i] == LC2K_LW
            || id2ex_pipe.opcode[i] == LC2K_JALR
            || id2ex_pipe.opcode[i] == LC2K_ADDI
            || id2ex_pipe.opcode[i] == LC2K_NAND);
    end
    endgenerate

    assign ex_wb_out.valid = id2ex_pipe.valid;
    assign ex_wb_out.opcode = id2ex_pipe.opcode;
    assign ex_wb_out.pc = id2ex_pipe.pc;
    assign ex_wb_out.destReg = id2ex_pipe.destReg;
    assign ex_wb_out.pred_taken = id2ex_pipe.pred_taken;
    assign ex_wb_out.result = result;
    assign ex_wb_out.mispredict = mispredict;
    assign ex_wb_out.branch_target = branch_target;

    ////////////////////////////////////////////////
    //                 btb update                 //
    ////////////////////////////////////////////////

    generate
    for (i = 0; i <= 1; ++i) begin : btb_update
        assign ex_wb_out.btb_update_en[i] = id2ex_pipe.valid[i] && id2ex_pipe.opcode[i] == LC2K_BEQ;
        assign ex_wb_out.btb_update_pc[i] = id2ex_pipe.pc[i];
        assign ex_wb_out.btb_update_target[i] = id2ex_pipe.pc[i] + id2ex_pipe.offset[i] + 1;
        assign ex_wb_out.btb_update_taken[i] = eq[i];
    end
    endgenerate

   
endmodule