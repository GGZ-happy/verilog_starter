/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  stage_id.sv                                         //
//                                                                     //
//  Description :  instruction decode (ID) stage of the pipeline;      //
//                 decode the instruction fetch register operands, and //
//                 compute immediate operand (if applicable)           //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

module stage_id (
    input   clock,          // system clock
    input   reset,          // system reset
    input   mispredict,
    input   load_complete,

    input COM_PACKET    wb2rf_pipe,

    input IF_PACKET     if2id_pipe,
    output ID_PACKET    id2ex_pipe,
    output logic    [1:0] insts_dispatched
);

    ID_PACKET next_id2ex_pipe;

    INST [3:0] insts;
    assign insts = if2id_pipe.insts;

    logic [`CACHE_BLOCK_OFFSET_BITS-1:0] line_buf_offset;
    assign line_buf_offset = if2id_pipe.pc[`CACHE_BLOCK_OFFSET_BITS-1:0];

    logic [1:0] regB_is_dest;
    logic [1:0] dest_is_dest;
    logic [1:0] reads_2_regs;
    logic [1:0] reads_regA;
    logic [1:0] accs_mem;

    genvar i;
    generate

    INST [1:0] next_insts;
    assign next_insts[0] = insts[line_buf_offset];
    assign next_insts[1] = (line_buf_offset + 1 < 3'd4) ? insts[line_buf_offset + 1] : '0;

    for (i = 0; i <= 1; ++i) begin : inst_decode
        assign next_id2ex_pipe.pc[i] = if2id_pipe.pc + i;
        assign next_id2ex_pipe.pred_taken[i] = if2id_pipe.pred_taken[i];
        assign next_id2ex_pipe.opcode[i] = next_insts[i].opcode;
        assign next_id2ex_pipe.regA[i] = next_insts[i].regA;
        assign next_id2ex_pipe.regB[i] = next_insts[i].regB;
        assign next_id2ex_pipe.offset[i] = next_insts[i].arg2.i.offset;
        // ADD, NOR, SW, BEQ, NAND read 2 regs
        // LW, JALR, ADDI read just regA
        assign regB_is_dest[i]
            = (next_id2ex_pipe.opcode[i] == LC2K_LW
            || next_id2ex_pipe.opcode[i] == LC2K_JALR
            || next_id2ex_pipe.opcode[i] == LC2K_ADDI);
        assign reads_2_regs[i]
            = (next_id2ex_pipe.opcode[i] == LC2K_ADD
            || next_id2ex_pipe.opcode[i] == LC2K_NOR
            || next_id2ex_pipe.opcode[i] == LC2K_SW
            || next_id2ex_pipe.opcode[i] == LC2K_BEQ
            || next_id2ex_pipe.opcode[i] == LC2K_NAND);
        assign accs_mem[i]
            = (next_id2ex_pipe.opcode[i] == LC2K_LW
            || next_id2ex_pipe.opcode[i] == LC2K_SW);
        assign reads_regA[i] = reads_2_regs[i] || regB_is_dest[i];
        assign dest_is_dest[i] = reads_2_regs[i]
            && next_id2ex_pipe.opcode[i] != LC2K_SW
            && next_id2ex_pipe.opcode[i] != LC2K_BEQ;
        assign next_id2ex_pipe.destReg[i]
            = regB_is_dest[i]
            ? next_insts[i].regB
            : next_insts[i].arg2.r.destReg;
    end
    endgenerate
    // Check if load hazard happen
    logic load_use_hazard;
    assign load_use_hazard = 
        (id2ex_pipe.valid[1] && id2ex_pipe.opcode[1] == LC2K_LW &&
            ((reads_regA[0] && next_id2ex_pipe.regA[0] == id2ex_pipe.destReg[1])
            || (reads_2_regs[0] && next_id2ex_pipe.regB[0] == id2ex_pipe.destReg[1])
            || (reads_regA[1] && next_id2ex_pipe.regA[1] == id2ex_pipe.destReg[1])
            || (reads_2_regs[1] && next_id2ex_pipe.regB[1] == id2ex_pipe.destReg[1])));

    // Validity/issue logic is tricky.
    logic RAW, WAW; // No need to do WAR here, but the uOpQ will need it
    assign RAW = (dest_is_dest[0] || regB_is_dest[0])
        && ((reads_regA[1] && next_id2ex_pipe.regA[1] == next_id2ex_pipe.destReg[0])
        || (reads_2_regs[1] && next_id2ex_pipe.regB[1] == next_id2ex_pipe.destReg[0]));
    assign WAW = (dest_is_dest[0] || regB_is_dest[0]) && (dest_is_dest[1] || regB_is_dest[1])
        && next_id2ex_pipe.destReg[0] == next_id2ex_pipe.destReg[1];

    // LS unit always uses entry/slot 1 of id2ex_pipe. Do actual switch in ff block
    // An issued branch doesn't invalidate the result of another issued memory op.
    // If a branch is issued with another non-memory op, inst 0 will go first
    logic swizzle;
    assign swizzle = accs_mem[0];
    assign next_id2ex_pipe.valid[0] = !mispredict && if2id_pipe.valid && !load_use_hazard;
    assign next_id2ex_pipe.valid[1] = !mispredict && next_id2ex_pipe.opcode[0] != LC2K_HALT
        && ((next_id2ex_pipe.opcode[0] != LC2K_BEQ && next_id2ex_pipe.opcode[0] != LC2K_JALR)
            || !accs_mem[1]) 
        && if2id_pipe.valid && !RAW && !WAW
        && !(accs_mem[0] && accs_mem[1])
        && (line_buf_offset + 1) < `CACHE_BLOCK_SIZE_IN_WORDS
        && !if2id_pipe.pred_taken[0];

    assign insts_dispatched = (!load_complete || load_use_hazard) ? 2'd0 :
                                (next_id2ex_pipe.valid == 2'b00) ? 2'd0 :
                                (next_id2ex_pipe.valid == 2'b11) ? 2'd2 : 2'd1;

    // Instantiate the register file
    regfile regs (
        .clock, // .name connects a port to a net of the same name
        .reset,
        .write_en   (wb2rf_pipe.wr_en),
        .write_idx  (wb2rf_pipe.destReg),
        .write_data (wb2rf_pipe.write_data),

        .read_idx   ({next_id2ex_pipe.regA, next_id2ex_pipe.regB}),
        .read_out   ({next_id2ex_pipe.valA, next_id2ex_pipe.valB})
    );

    always_ff @(posedge clock) begin
        if (reset) begin
            id2ex_pipe <= '0;
        end else if (load_complete && !load_use_hazard) begin
            if (swizzle) begin
                id2ex_pipe.valid      <= {next_id2ex_pipe.valid[0],       next_id2ex_pipe.valid[1]};
                id2ex_pipe.pred_taken <= {next_id2ex_pipe.pred_taken[0],  next_id2ex_pipe.pred_taken[1]};
                id2ex_pipe.opcode     <= {next_id2ex_pipe.opcode[0],      next_id2ex_pipe.opcode[1]};
                id2ex_pipe.pc         <= {next_id2ex_pipe.pc[0],          next_id2ex_pipe.pc[1]};
                id2ex_pipe.regA       <= {next_id2ex_pipe.regA[0],        next_id2ex_pipe.regA[1]};
                id2ex_pipe.regB       <= {next_id2ex_pipe.regB[0],        next_id2ex_pipe.regB[1]};
                id2ex_pipe.destReg    <= {next_id2ex_pipe.destReg[0],     next_id2ex_pipe.destReg[1]};
                id2ex_pipe.offset     <= {next_id2ex_pipe.offset[0],      next_id2ex_pipe.offset[1]};
                id2ex_pipe.valA       <= {next_id2ex_pipe.valA[0],        next_id2ex_pipe.valA[1]};
                id2ex_pipe.valB       <= {next_id2ex_pipe.valB[0],        next_id2ex_pipe.valB[1]};
            end else begin
                id2ex_pipe <= next_id2ex_pipe;
            end
        end else if (load_complete && load_use_hazard) begin
                id2ex_pipe <= '0;  // insert bubble
        end // else leave id2ex_pipe as-is
    end
endmodule // stage_id
