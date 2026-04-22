/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.svh                                        //
//                                                                     //
//  Description :  This file defines pipeline register data structures //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_SVH__
`define __SYS_DEFS_SVH__

`include "../test/mem.svh"

// Define parameters
// Icache-related
`define ICACHE_NUM_LINES 16
// BTB-related
`define BTB_ENTRIES 8
`define BANKS 2
// uOPQ-related
`define UOPQ_DEPTH 8

/* "Packets" are used to move many variables between modules with
 * just one datatype, but can be cumbersome in some circumstances.
 * Modify these or define new ones in this file at your own discretion.
*/

// IF Packet: Data exchanged from IF to the next stage
typedef struct packed {
    logic valid;
    logic [1:0] pred_taken;
    ADDR pc;
    MEM_BLOCK insts;
} IF_PACKET;

// ID Packet: Data exchanged from ID to the next stage
typedef struct packed {
    logic       [1:0] valid;
    logic       [1:0] pred_taken;
    LC2K_OPCODE [1:0] opcode;
    ADDR        [1:0] pc;
    REG_IDX     [1:0] regA;
    REG_IDX     [1:0] regB;
    REG_IDX     [1:0] destReg;
    ADDR        [1:0] offset;
    WORD        [1:0] valA;
    WORD        [1:0] valB;
} ID_PACKET;

// EX/WB Packet: Data exchanged from EX to WB stage
typedef struct packed {
    logic       [1:0] valid;
    logic       [1:0] wr_en;
    LC2K_OPCODE [1:0] opcode;
    ADDR        [1:0] pc;
    REG_IDX     [1:0] destReg;
    WORD        [1:0] result;
    logic       [1:0] pred_taken;
    logic       [1:0] mispredict;
    ADDR        [1:0] branch_target;
    WORD              store_data;
    MEM_COMMAND       mem_command;
    ADDR              ls_addr;
    // btb information
    logic       [1:0] btb_update_en;
    ADDR        [1:0] btb_update_pc;
    ADDR        [1:0] btb_update_target;
    logic       [1:0] btb_update_taken;
} EX_WB_PACKET;

// COM Packet: Tracking info from the writeback stage back to the register file
typedef struct packed {
    logic   [2:0] valid;
    logic   [1:0] wr_en;
    EXCEPTION_CODE error_status;
    logic       mispredict;
    ADDR        next_pc;
    REG_IDX [1:0] destReg;
    WORD    [1:0] write_data;
} COM_PACKET;

`endif // __SYS_DEFS_SVH__