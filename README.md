# NEW EECS 470

Welcome to the NEW EECS 470 VeriSimple2K Processor!

This is the repository for a 2-way, pipelined, synthesizable, LC2K processor.

The provided implementation has only 3 stages and thus avoids data forwarding.
Data hazards are instead handled by the issue logic in the decode stage.
The provided processor is correct, and it will produce the correct output 
for all programs, but it has a miserable CPI and clock period.

Some sample assembly programs are provided in `programs/` to
expose a buggy processor via memory correctness.
An assembler for LC2K is also provided, and works on CAEN systems.
Other test assembly programs should be placed here.

### Files

In this folder, you are provided with most of the code and the entire
build and test system. This is a quick overview of the Makefile and the
verilog files you will be editing.

The VeriSimple2K pipeline is broken up into files in the `verilog/` folder.
There are 2 headers used by the `verilog/` folder and the testbench:
`mem.svh` and `ISA.svh` found in the `test/` folder, which you may not modify.
`mem.svh` defines memory-specific types, and `ISA.svh` defines 
decoding information used by the ID stage and bitwidths everywhere.
`verilog/sys_defs.svh` defines the shapes for the pipeline registers
between stages. The stages are present in `stage_{if,id,com}.sv`.
The register file is in `regfile.sv` and is instantiated inside the ID stage.
Finally, the stages are tied together by the cpu module in `cpu.sv`.

The testbench and associated non-synthesizable verilog can be found in the `test/` folder.
Note that the memory module defined in `test/mem.sv` is **not synthesizable**.

### Getting Started

See the milestones described in the spec to determine the best starting point.

## Makefile Target Reference

Look at the top of `Makefile` to see the table of contents and many
of the commands available with `make`.

`make <my_program>.out` should be your main command for running
programs: it creates the `<my_program>.fmem`, `<my_program>.cpi`,
`<my_program>.wb`, and `<my_program>.ppln` final memory, CPI, writeback,
and pipeline output files in the `output/` directory. The output file
includes the processor status and the final state of memory, the CPI
file contains the total runtime and CPI calculation, the writeback file
is the list of writes to registers done by the program, and the pipeline
file is the state of each of the pipeline stages as the program is run.