/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  stage_if.sv                                         //
//                                                                     //
//  Description :  instruction fetch (IF) stage of the pipeline;       //
//                 fetch instruction, compute pred next PC location,   //
//                 and send down the pipeline.                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

module stage_if (
    input           clock,          // system clock
    input           reset,          // system reset

    input [1:0]     insts_dispatched,
    input           mispredict,
    input ADDR      next_pc,

    input MEM_BLOCK ic_data,  // data coming back from Instruction memory
    input ADDR      ic_addr,  // addr of data coming back from Instruction memory
    input           ic_valid, // data coming back from Instruction memory is valid

    output ADDR     if_addr, // address sent to Instruction memory

    output ADDR     dbg_if_PC,
    output IF_PACKET if2id_pipe,

    // btb port from WB
    input logic     [1:0] btb_update_en,
    input ADDR      [1:0] btb_update_pc,
    input ADDR      [1:0] btb_update_target
);
    //////////////////////////////////////////////////
    //                                              //
    //               PC management                  //
    //                                              //
    //////////////////////////////////////////////////  

    ADDR PC_reg;    // PC we are currently fetching
    assign dbg_if_PC = PC_reg;

    // Get the start address without offset
    ADDR PC_line_addr;
    logic [$bits(ADDR)-1:`CACHE_BLOCK_OFFSET_BITS] PC_line;
    assign PC_line = PC_reg[$bits(ADDR)-1:`CACHE_BLOCK_OFFSET_BITS];
    assign PC_line_addr = {PC_line, `CACHE_BLOCK_OFFSET_BITS'b0}; 
    assign if_addr = PC_line_addr;

    // Get the offset
    logic [`CACHE_BLOCK_OFFSET_BITS-1:0] line_buf_offset;
    assign line_buf_offset = if2id_pipe.pc[`CACHE_BLOCK_OFFSET_BITS-1:0];

    //////////////////////////////////////////////////
    //                                              //
    //                   btb                        //
    //                                              //
    //////////////////////////////////////////////////  

    ADDR [3:0] line_pcs;
    assign line_pcs[0] = PC_line_addr;
    assign line_pcs[1] = PC_line_addr + 1;
    assign line_pcs[2] = PC_line_addr + 2;
    assign line_pcs[3] = PC_line_addr + 3;

    logic [3:0] raw_pred;
    ADDR  [3:0] raw_tgt;

    btb btb_inst (
        .clock,
        .reset,
        .lookup_pc(line_pcs),
        .hit(raw_pred),
        .target(raw_tgt),
        .update_en(btb_update_en),
        .update_pc(btb_update_pc),
        .update_target(btb_update_target)
    ); // btb

    //////////////////////////////////////////////////
    //                                              //
    //                   IF logic                   //
    //                                              //
    //////////////////////////////////////////////////

    // Only predict the first branch
    logic [`CACHE_BLOCK_OFFSET_BITS-1:0] start_off;
    assign start_off = PC_reg[`CACHE_BLOCK_OFFSET_BITS-1:0];

    logic [3:0] masked_pred;
    always_comb begin
        masked_pred = '0;
        if (start_off <= 2'd0 && raw_pred[0]) masked_pred[0] = 1'b1;
        else if (start_off <= 2'd1 && raw_pred[1]) masked_pred[1] = 1'b1;
        else if (start_off <= 2'd2 && raw_pred[2]) masked_pred[2] = 1'b1;
        else if (raw_pred[3]) masked_pred[3] = 1'b1;
    end //明天从这里开始

    // Check if this buffer is fully dispatched
    logic fully_dispatched;
    assign fully_dispatched = !if2id_pipe.valid || (line_buf_offset + insts_dispatched) == 3'd4;
    // Check if the next buffer line is prepared
    logic next_line_buf_valid;
    assign next_line_buf_valid = ic_valid && ic_addr == PC_line_addr;

    ADDR NPC;  // address of inst we're fetching in the next cycle
    // When there's a mispredict, unconditionally take the next PC from EX
    // Otherwise push the next cache line when the last is fully dispatched
    assign NPC = mispredict ? next_pc : // jump to next pc if mispredict
        btb_hit ? btb_target : // jump to predicted pc target
        (fully_dispatched && next_line_buf_valid) 
            ? (PC_line_addr + `CACHE_BLOCK_SIZE_IN_WORDS) //jump to new buffer line if is fully dispatched
            : PC_reg;

    always_ff @(posedge clock) begin
        if (reset) begin
            PC_reg <= '0;
        end else begin
            PC_reg <= NPC;
        end
        if (reset) begin
            if2id_pipe.valid      <= `FALSE;
            if2id_pipe.pred_taken <= '0;
            if2id_pipe.pc         <= '0;
            if2id_pipe.insts      <= '0;
        end else if (btb_hit && if2id_pipe.valid) begin //btb hit
            if2id_pipe.pred_taken[line_buf_offset] <= 1'b1; //predictor label
            if2id_pipe.pc <= if2id_pipe.pc + insts_dispatched;
        end else if (mispredict || (fully_dispatched && !next_line_buf_valid)) begin //mispredict or not prepared
            if2id_pipe.valid      <= `FALSE;
        end else if (fully_dispatched /*&& next_line_buf_valid*/) begin
            if2id_pipe.valid      <= `TRUE;
            if2id_pipe.pc         <= PC_reg;
            if2id_pipe.insts      <= ic_data;
        end else /*if (!mispredict && !fully_dispatched)*/ begin
            // if2id_pipe.valid must be true
            if2id_pipe.pc         <= if2id_pipe.pc + insts_dispatched;
        end
    end
endmodule // stage_if