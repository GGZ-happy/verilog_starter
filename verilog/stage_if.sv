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
    output IF_PACKET if2id_pipe
);

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