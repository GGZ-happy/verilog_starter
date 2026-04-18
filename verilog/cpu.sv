/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu.sv                                              //
//                                                                     //
//  Description :  Top-level module of the VeriSimple processor;       //
//                 This instantiates and connects the stages of the    //
//                 pipeline together.                                  //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

module cpu (
    input clock,    // System clock
    input reset,    // System reset

    // Memory inputs and outputs
    input MEM_BLOCK [`BUS_WIDTH-1:0] mem2proc_data,  // Data coming back from memory
    input ADDR      [`BUS_WIDTH-1:0] mem2proc_addr,  // Address of data coming back from memory
    input           [`BUS_WIDTH-1:0] mem2proc_valid, // Indicator that memory is sending data

    output MEM_COMMAND  proc2mem_command,       // Command sent to memory
    output WORD         proc2mem_data,          // Data sent to memory
    output ADDR [`BUS_WIDTH-1:0] proc2mem_addr, // Address sent to memory

    // Debug outputs: these signals are used for 
    // halting the testbench and printing to files.
    output ADDR         dbg_if_PC,
    output ADDR         dbg_id_PC,
    output MEM_BLOCK    dbg_id_insts,
    output logic        dbg_id_valid,
    output ADDR         [1:0] dbg_ex_PC,
    output LC2K_OPCODE  [1:0] dbg_ex_opcd,
    output REG_IDX      [1:0] dbg_ex_opr1,
    output ADDR         [1:0] dbg_ex_opr2,
    output ADDR         [1:0] dbg_ex_dest,
    output logic        [1:0] dbg_ex_valid,
    output logic        [1:0] dbg_wb_wren,
    output REG_IDX      [1:0] dbg_wb_idx,
    output WORD         [1:0] dbg_wb_data,
    output logic        [2:0] dbg_wb_valid,
    output EXCEPTION_CODE error_status
);

    // You may modify anything in the verilog/ directory except the above interface.
    // You may also add new files.

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////

    // Outputs from IF stage and IF/ID Pipeline Register
    IF_PACKET if2id_pipe;

    // Outputs from ID stage and ID/EX Pipeline Register
    ID_PACKET id2ex_pipe;

    // Outputs from WB stage and (later) EX/WB Pipeline Register
    COM_PACKET wb2rf_pipe;

    // Pipeline backwards paths
    logic [1:0] insts_dispatched;
    logic load_complete;
    logic mispredict;
    ADDR  next_pc;

    assign load_complete = wb2rf_pipe.valid[1];
    // For this impl of EX, LS unit always uses inst 1
    assign mispredict = wb2rf_pipe.mispredict;
    assign next_pc = wb2rf_pipe.next_pc;

    //////////////////////////////////////////////////
    //                                              //
    //                   icache                     //
    //                                              //
    //////////////////////////////////////////////////    

    ADDR ic_addr;
    MEM_BLOCK ic_data;
    logic ic_valid;
    ADDR if_addr;

    icache #(.NUM_LINES(`ICACHE_NUM_LINES)) ic (
        .clock,
        .reset,
        .if_addr,
        .ic_addr,
        .ic_data,
        .ic_valid,
        .ic2mem_addr(proc2mem_addr[1]),
        .mem_valid(mem2proc_valid[1]),
        .mem_data(mem2proc_data[1]),
        .mem_addr(mem2proc_addr[1])
    );

    
    ////////////////////////////////////////////////
    //                                            //
    //                 btb update                 //
    //                                            //
    ////////////////////////////////////////////////

    logic [1:0] btb_update_en;
    ADDR  [1:0] btb_update_pc;
    ADDR  [1:0] btb_update_target;

    //////////////////////////////////////////////////
    //                                              //
    //                   Stages                     //
    //                                              //
    //////////////////////////////////////////////////


    stage_if if_stage (
        // Inputs
        .clock,
        .reset,
        .insts_dispatched,
        .mispredict,
        .next_pc,
        .ic_data,
        .ic_addr,
        .ic_valid,
        .if_addr,
        .dbg_if_PC,
        .if2id_pipe,
        .btb_update_en,
        .btb_update_pc,
        .btb_update_target
    );

    stage_id id_stage (
        .clock,
        .reset,
        .mispredict,
        .load_complete,
        .wb2rf_pipe,
        .if2id_pipe,
        .id2ex_pipe,
        .insts_dispatched
    );

    stage_com com_stage (
        .id2ex_pipe,
        .mem2proc_data,
        .mem2proc_addr,
        .mem2proc_valid,
        .proc2mem_data,
        .ls2mem_addr(proc2mem_addr[0]),
        .ls2mem_command(proc2mem_command),
        .wb2rf_pipe,
        .btb_update_en,
        .btb_update_pc,
        .btb_update_target
    );

    //////////////////////////////////////////////////
    //                                              //
    //                Debug Signals                 //
    //                                              //
    //////////////////////////////////////////////////

    // These signals debug what is happening inside a 
    // stage, determined by outputs from the previous.
    // dbg_if_PC handled by stage_if
    assign dbg_id_PC = if2id_pipe.pc;
    assign dbg_id_insts = if2id_pipe.insts;
    assign dbg_id_valid = if2id_pipe.valid;
    assign dbg_ex_PC = id2ex_pipe.pc;
    assign dbg_ex_opcd = id2ex_pipe.opcode;
    assign dbg_ex_opr1 = id2ex_pipe.regA;
    assign dbg_ex_opr2 = id2ex_pipe.regB;
    assign dbg_ex_dest = id2ex_pipe.offset;
    assign dbg_ex_valid = id2ex_pipe.valid;
    assign dbg_wb_wren = wb2rf_pipe.wr_en;
    assign dbg_wb_idx = wb2rf_pipe.destReg;
    assign dbg_wb_data = wb2rf_pipe.write_data;
    assign dbg_wb_valid[2] = `FALSE; // Change if adding width to backend
    assign dbg_wb_valid[1:0] = wb2rf_pipe.valid;
    assign error_status = wb2rf_pipe.error_status;
endmodule // cpu
