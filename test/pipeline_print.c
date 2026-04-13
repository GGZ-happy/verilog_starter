/*
 *  pipe_print.c - Print instructions as they pass through the verisimple
 *                 pipeline.  Must compile with the '+vc' vcs flag.
 *
 *  Doug MacKay <dmackay@umich.edu> Fall 2003
 *
 *  Updated for RISC-V by C Jones, Winter 2019
 *
 *  Updated to take an arbitrary file by Ian W, Winter 2023
 *
 *  Output format improved by Ian in Winter 2024
 * 
 *  Updated for 2-way LC2K by Mason Nelson, Fall 2025
 */

#include <stdio.h>

// Return a string of an LC2K instruction's opcode name.
char* decode_opcode(int inst)
{
    switch ((inst >> 28) & 0xf) {
        case 0: return "add";
        case 1: return "nor";
        case 2: return "lw";
        case 3: return "sw";
        case 4: return "beq";
        case 5: return "jalr";
        case 6: return "halt";
        case 7: return "noop";
        case 8: return "addi";
        case 9: return "nand";
        default: return "JUNK";
    }
}

int rA(int inst) { return (inst >> 24) & 0xf; }
int rB(int inst) { return (inst >> 20) & 0xf; }
int off(int inst) { return inst & 0xfffff; }

static FILE* pipeFile = NULL;

void open_pipeline_output_file(char* file_name)
{
    pipeFile = fopen(file_name, "w");
}

void close_pipeline_output_file()
{
    fprintf(pipeFile, "\n");
    fclose(pipeFile);
    pipeFile = NULL;
}

void print_header()
{
    fprintf(pipeFile, "Cycle  |PC/IF|%5s/%-59s|%10s/%-10s|%11s %-11s| MEM Bus",
        "IF", "ID", "ID", "EX", "Reg", "WB");
}

void print_cycles(int clock_count)
{
    fprintf(pipeFile, "\n%6d ", clock_count);
}

void print_pc(int pc, int fetch)
{
    if (!fetch) fprintf(pipeFile, "|     ");
    else fprintf(pipeFile, "|%5X", pc);
}

void print_ifid(int pc, int valid_line, int i0, int i1, int i2, int i3)
{
    if (!valid_line) fprintf(pipeFile, "|%5s:%-59s", "-", "-");
    else fprintf(pipeFile, "|%5X:%4s %X %X %05X,%4s %X %X %05X,%4s %X %X %05X,%4s %X %X %05X", pc,
        decode_opcode(i0), rA(i0), rB(i0), off(i0),
        decode_opcode(i1), rA(i1), rB(i1), off(i1),
        decode_opcode(i2), rA(i2), rB(i2), off(i2),
        decode_opcode(i3), rA(i3), rB(i3), off(i3));
}

void print_idex(int pcA, int opcdA, int opr1A, int opr2A, int destA, int valid_instA, 
    int pcB, int opcdB, int opr1B, int opr2B, int destB, int valid_instB)
{
    if (!valid_instA) fprintf(pipeFile, "|%10s", " ");
    else fprintf(pipeFile, "|%5X:%4s", pcA, decode_opcode(opcdA), opr1A, opr2A, destA);
    if (!valid_instB) fprintf(pipeFile, ",%10s", " ");
    else fprintf(pipeFile, ",%5X:%4s", pcB, decode_opcode(opcdB), opr1B, opr2B, destB);
}

void print_reg(int wb_dataA, int wb_idxA, int wb_validA, int wb_dataB, int wb_idxB, int wb_validB)
{
    if (!wb_validA) fprintf(pipeFile, "|           ");
    else fprintf(pipeFile, "|r%X=%-08X", wb_idxA, wb_dataA);
    if (!wb_validB) fprintf(pipeFile, ",           ");
    else fprintf(pipeFile, ",r%X=%-08X", wb_idxB, wb_dataB);
}

void print_membus(int proc2mem_command, int proc2mem_addr, int proc2mem_data)
{
    if (proc2mem_command == 1)
        fprintf(pipeFile, "| LOAD  [%5X]", proc2mem_addr);
    else if (proc2mem_command == 2)
        fprintf(pipeFile, "| STORE [%5X] = %X", proc2mem_addr, proc2mem_data);
    else
        fprintf(pipeFile, "|");
}
