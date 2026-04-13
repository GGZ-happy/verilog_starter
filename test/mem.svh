/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  mem.svh                                             //
//                                                                     //
//  Description :  This file defines macros and data structures used   //
//                 by the memory hierarchy.                            //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __MEM_SVH__
`define __MEM_SVH__

`include "../test/ISA.svh"

`timescale 1ns/100ps

//////////////////////////////////
// ---- Memory Definitions ---- //
//////////////////////////////////

// NOTE: the global CLOCK_PERIOD is defined in cpu.clock
`define MEM_LATENCY_IN_CYCLES $rtoi((35.0-`CLOCK_PERIOD)/`CLOCK_PERIOD+0.49999)
`define BUS_WIDTH 2

`define CACHE_BLOCK_OFFSET_BITS 2
`define CACHE_BLOCK_SIZE_IN_WORDS (1 << `CACHE_BLOCK_OFFSET_BITS)
`define MEM_SIZE_IN_WORDS (1 << ($bits(ADDR)-1))
`define MEM_CACHE_LINES (`MEM_SIZE_IN_WORDS/`CACHE_BLOCK_SIZE_IN_WORDS)

// Memory bus commands
typedef enum logic [1:0] {
    MEM_NONE   = 2'h0,
    MEM_LOAD   = 2'h1,
    MEM_STORE  = 2'h2
} MEM_COMMAND;

// A memory or cache block
typedef WORD [`CACHE_BLOCK_SIZE_IN_WORDS-1:0] MEM_BLOCK;

`endif // __MEM_SVH__