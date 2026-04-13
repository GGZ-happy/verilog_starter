/////////////////////////////////////////////////////////////////////////
//                                                                     //
//     Filename :  ISA.svh                                             //
//                                                                     //
//  Description :  This file contains global definitions for all       //
//                 LC2K ISA related things.                            //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __ISA_SVH__
`define __ISA_SVH__

// useful boolean single-bit definitions
`define FALSE 1'b0
`define TRUE  1'b1

// LC2K Opcodes
typedef enum logic [3:0] {
    LC2K_ADD  = 4'b0000,
    LC2K_NOR  = 4'b0001,
    LC2K_LW   = 4'b0010,
    LC2K_SW   = 4'b0011,
    LC2K_BEQ  = 4'b0100,
    LC2K_JALR = 4'b0101,
    LC2K_HALT = 4'b0110,
    LC2K_NOOP = 4'b0111,
    LC2K_ADDI = 4'b1000,
    LC2K_NAND = 4'b1001
} LC2K_OPCODE;

`define LC2K_NOOPINST {LC2K_NOOP, 28'b0}

// word and register sizes
typedef logic signed [31:0] WORD;
typedef logic signed [19:0] ADDR;
typedef logic [3:0]  REG_IDX;

typedef struct packed {
    LC2K_OPCODE opcode;
    REG_IDX regA;
    REG_IDX regB;
    union packed {
        struct packed {
            ADDR offset;
        } i; // Immediate instructions
        struct packed {
            logic[15:0] unused;
            REG_IDX destReg;
        } r; // Register instructions
    } arg2;
} INST;

///////////////////////////////
// ---- Exception Codes ---- //
///////////////////////////////

/* Exception codes for when something goes wrong in the processor.
 * Note that we use HALTED to signify the end of computation.
*/

typedef enum logic [1:0] {
    NO_ERROR         = 2'h0,
    HALTED           = 2'h1,
    ILLEGAL_INST     = 2'h2,
    MEM_ACCESS_FAULT = 2'h3
} EXCEPTION_CODE;

`endif // __ISA_SVH__
