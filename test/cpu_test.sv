/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu_test.sv                                         //
//                                                                     //
//  Description :  Testbench module for the VeriSimple2K processor.    //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "../test/mem.svh"

`ifndef VERDI
// These link to the pipe_print.c file in this directory, and are used below to print
// detailed output to the pipeline_output_file, initialized by open_pipeline_output_file()
import "DPI-C" function void open_pipeline_output_file(string file_name);
import "DPI-C" function void close_pipeline_output_file();
import "DPI-C" function void print_header();
import "DPI-C" function void print_cycles(int clock_count);
import "DPI-C" function void print_pc(int pc, int fetch);
import "DPI-C" function void print_ifid(int pc, int valid_line, int i0, int i1, int i2, int i3);
import "DPI-C" function void print_idex(int pcA, int opcdA, int opr1A, int opr2A, int destA, int valid_instA, 
    int pcB, int opcdB, int opr1B, int opr2B, int destB, int valid_instB);
import "DPI-C" function void print_reg(int wb_dataA, int wb_idxA, int wb_validA, int wb_dataB, int wb_idxB, int wb_validB);
import "DPI-C" function void print_membus(int proc2mem_command, int proc2mem_addr, int proc2mem_data);
`endif


module testbench;
    // string inputs for loading memory and output files
    // run like: cd build && ./simv +MEMORY=../programs/mem/<my_program>.mem +OUTPUT=../output/<my_program>
    // this testbench will generate 4 output files based on the output
    // named OUTPUT.{out cpi, wb, ppln} for the memory, cpi, writeback, and pipeline outputs.
    string program_memory_file, output_name;
    string out_outfile, fmem_outfile, cpi_outfile, writeback_outfile, pipeline_outfile;
    int out_fileno, fmem_fileno, cpi_fileno, wb_fileno; // verilog uses integer file handles with $fopen and $fclose

    // variables used in the testbench
    logic       clock;
    logic       reset;
    int         clock_count; // also used for terminating infinite loops
    int         instr_count;

    MEM_COMMAND proc2mem_command;
    WORD        proc2mem_data;
    ADDR        [`BUS_WIDTH-1:0] proc2mem_addr;
    MEM_BLOCK   [`BUS_WIDTH-1:0] mem2proc_data;
    ADDR        [`BUS_WIDTH-1:0] mem2proc_addr;
    logic       [`BUS_WIDTH-1:0] mem2proc_valid;

    ADDR    dbg_if_PC;
    ADDR    dbg_id_PC;
    MEM_BLOCK   dbg_id_insts;
    logic   dbg_id_valid;
    ADDR    [1:0] dbg_ex_PC;
    LC2K_OPCODE [1:0] dbg_ex_opcd;
    REG_IDX [1:0] dbg_ex_opr1;
    ADDR    [1:0] dbg_ex_opr2;
    ADDR    [1:0] dbg_ex_dest;
    logic   [1:0] dbg_ex_valid;
    logic   [1:0] dbg_wb_wren;
    REG_IDX [1:0] dbg_wb_idx;
    WORD    [1:0] dbg_wb_data;
    logic   [2:0] dbg_wb_valid;
    EXCEPTION_CODE error_status;

    // Instantiate the Data Memory
    mem memory (
        .clock,
        .reset,
        .proc2mem_command,
        .proc2mem_data,
        .proc2mem_addr,
        .mem2proc_data,
        .mem2proc_addr,
        .mem2proc_valid,
        .stdout_fileno (out_fileno)
    ); // Could use .* to automatically connect all ports and nets with the same name

    // Instantiate the Pipeline
    cpu yourCPU (
        .clock,
        .reset,
        .mem2proc_data,
        .mem2proc_addr,
        .mem2proc_valid,
        .proc2mem_command,
        .proc2mem_data,
        .proc2mem_addr,
        .dbg_if_PC,
        .dbg_id_PC,
        .dbg_id_insts,
        .dbg_id_valid,
        .dbg_ex_PC,
        .dbg_ex_opcd,
        .dbg_ex_opr1,
        .dbg_ex_opr2,
        .dbg_ex_dest,
        .dbg_ex_valid,
        .dbg_wb_wren,
        .dbg_wb_idx,
        .dbg_wb_data,
        .dbg_wb_valid,
        .error_status
    ); // Can't do .* for connecting to a synthesized module


    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end


    initial begin
        $display("\n---- Starting CPU Testbench ----\n");

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Using memory file  : %s", program_memory_file);
        end else begin
            $display("Did not receive '+MEMORY=' argument. Exiting.\n");
            $finish;
        end
        if ($value$plusargs("OUTPUT=%s", output_name)) begin
            $display("Using output files : %s.{out, fmem, cpi, wb, ppln}", output_name);
            out_outfile       = {output_name,".out"}; // this is how you concatenate strings in verilog
            fmem_outfile      = {output_name,".fmem"};
            cpi_outfile       = {output_name,".cpi"};
            writeback_outfile = {output_name,".wb"};
            pipeline_outfile  = {output_name,".ppln"};
        end else begin
            $display("\nDid not receive '+OUTPUT=' argument. Exiting.\n");
            $finish;
        end

        $dumpfile({output_name, ".vcd"});
        $dumpvars(0);
        $dumplimit(629145600);

        clock = 1'b1;

        $display("\n  %16t : Asserting Reset", $realtime);
        reset = `TRUE;

        @(posedge clock);
        @(negedge clock);

        $display("  %16t : Loading Unified Memory", $realtime);
        // load the compiled program's hex data into the memory module
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        #0.1; // This reset is at an odd time to avoid the pos & neg clock edges
        $display("  %16t : Deasserting Reset", $realtime);
        reset = `FALSE;

        wb_fileno = $fopen(writeback_outfile);
        out_fileno = $fopen(out_outfile);
        $fdisplay(wb_fileno, "Memory writeback output (hexadecimal : decimal : ascii)");

        // Open pipeline output file AFTER throwing the reset otherwise the reset state is displayed
        open_pipeline_output_file(pipeline_outfile);
        print_header();

        $display("  %16t : Running Processor", $realtime);
    end


    always @(negedge clock) begin
        if (reset) begin
            // Count the number of cycles and number of instructions committed
            clock_count = 0;
            instr_count = 0;
        end else begin
            #2; // wait a short time to avoid a clock edge

            clock_count = clock_count + 1;
            if (dbg_wb_valid[0]) instr_count = instr_count + 1;
            if (dbg_wb_valid[1]) instr_count = instr_count + 1;
            if (dbg_wb_valid[2]) instr_count = instr_count + 1;

            if (clock_count % 1000 == 0) begin
                $display("  %16t : %d cycles", $realtime, clock_count);
            end
`ifndef VERDI
            // print the pipeline debug outputs via c code to the pipeline output file
            print_cycles(clock_count - 1);
            print_pc  ({12'b0, dbg_if_PC}, 1);
            print_ifid({12'b0, dbg_id_PC}, {31'b0, dbg_id_valid}, 
                dbg_id_insts[0], dbg_id_insts[1], dbg_id_insts[2], dbg_id_insts[3]);
            print_idex({12'b0, dbg_ex_PC[0]}, {dbg_ex_opcd[0], 28'b0}, {28'b0, dbg_ex_opr1[0]}, {12'b0, dbg_ex_opr2[0]}, {12'b0, dbg_ex_dest[0]}, {31'b0, dbg_ex_valid[0]}, 
                       {12'b0, dbg_ex_PC[1]}, {dbg_ex_opcd[1], 28'b0}, {28'b0, dbg_ex_opr1[1]}, {12'b0, dbg_ex_opr2[1]}, {12'b0, dbg_ex_dest[1]}, {31'b0, dbg_ex_valid[1]});
            print_reg(dbg_wb_data[0], {28'b0, dbg_wb_idx[0]}, {31'b0, dbg_wb_wren[0]},
                      dbg_wb_data[1], {28'b0, dbg_wb_idx[1]}, {31'b0, dbg_wb_wren[1]});
            print_membus({30'b0, proc2mem_command}, {12'b0, proc2mem_addr[0]}, proc2mem_data);
`endif
            if (proc2mem_command == MEM_STORE) begin
                $fdisplay(wb_fileno, "*0x%x = 0x%8x : %d", proc2mem_addr[0], proc2mem_data, proc2mem_data);
                // if (proc2mem_data > 31 && proc2mem_data < 127)
                //     $fdisplay(wb_fileno, "*0x%x = 0x%x : %6d : '%c'",
                //         proc2mem_addr[0], proc2mem_data, proc2mem_data, proc2mem_data);
                // else
                //     $fdisplay(wb_fileno, "*0x%x = 0x%x : %6d",
                //         proc2mem_addr[0], proc2mem_data, proc2mem_data);
            end

            // stop the processor
            if (error_status != NO_ERROR || clock_count == 200000) begin
                $display("  %16t : Processor Finished", $realtime);

                // close the writeback and pipeline output files
                close_pipeline_output_file();
                $fclose(out_fileno);

                // display the final memory, status, and instruction count
                show_final_mem_and_status(error_status);
                $fclose(wb_fileno);
                // output the final CPI
                output_cpi_file();

                $display("\n---- Finished CPU Testbench ----\n");

                #1 $finish;
            end
        end // else if (!reset)
    end // always @(negedge clock)

    // Task to output the final CPI and # of elapsed clock edges
    task output_cpi_file;
        real cpi;
        real exectime;
        real tpi;
        begin
            cpi = $itor(clock_count) / instr_count; // must convert int to real
            exectime = $itor(clock_count) * `CLOCK_PERIOD;
            tpi = exectime / instr_count;
            cpi_fileno = $fopen(cpi_outfile);
            $fdisplay(cpi_fileno, "@@@  %0d cycles / %0d instrs = %f CPI",
                clock_count, instr_count, cpi);
            $fdisplay(cpi_fileno, "@@@  %4.2f ns total time to execute",
                exectime);
            $fdisplay(cpi_fileno, "@@@  %4.2f ns per instruction",
                tpi);
            $fclose(cpi_fileno);
        end
    endtask // task output_cpi_file

    // Show contents of Unified Memory in both hex and decimal
    // Also output the final processor status
    task show_final_mem_and_status;
        input EXCEPTION_CODE final_status;
        int showing_data;
        begin
            fmem_fileno = $fopen(fmem_outfile);
            $fdisplay(fmem_fileno, "Exit status:");
            case (final_status)
                HALTED:           $fdisplay(fmem_fileno, "@@@ System halted after %0d instructions", instr_count);
                ILLEGAL_INST:     $fdisplay(fmem_fileno, "@@@ System halted on illegal instruction");
                MEM_ACCESS_FAULT: $fdisplay(fmem_fileno, "@@@ System halted on memory error");
                default:          $fdisplay(fmem_fileno, "@@@ System halted on timeout or unknown error");
            endcase
            $fdisplay(wb_fileno, "Exit status:");
            case (final_status)
                HALTED:           $fdisplay(wb_fileno, "@@@ System halted after %0d instructions", instr_count);
                ILLEGAL_INST:     $fdisplay(wb_fileno, "@@@ System halted on illegal instruction");
                MEM_ACCESS_FAULT: $fdisplay(wb_fileno, "@@@ System halted on memory error");
                default:          $fdisplay(wb_fileno, "@@@ System halted on timeout or unknown error");
            endcase
            $fdisplay(fmem_fileno, "Final Unified Memory contents (hexadecimal : decimal : ascii):");
            showing_data = 1;
            for (ADDR k = 0; k < `MEM_SIZE_IN_WORDS - 1; k = k+1) begin // Omit mem[0xfffff]
                if (memory.unified_memory[k] != 0) begin
                    $fdisplay(fmem_fileno, "@@@ mem[0x%5x] = 0x%5x : %d", k, 
                        memory.unified_memory[k], memory.unified_memory[k]);
                    showing_data = 1;
                end else if (showing_data != 0) begin
                    $fdisplay(fmem_fileno, "@@@");
                    showing_data = 0;
                end
            end

            // for (ADDR k = 0; 0 <= k && k <= `MEM_SIZE_IN_WORDS - 1; k = k+1) begin  // Omit mem[0xfffff]
            //     if (memory.unified_memory[k] > 31 && memory.unified_memory[k] < 127) begin
            //         $fdisplay(fmem_fileno, "@@@ mem[0x%x] = 0x%x : %6d : '%c'", k,
            //             memory.unified_memory[k], memory.unified_memory[k], memory.unified_memory[k]);
            //         showing_data = 1;
            //     end else if (memory.unified_memory[k] != 0) begin
            //         $fdisplay(fmem_fileno, "@@@ mem[0x%x] = 0x%x : %6d", k,
            //             memory.unified_memory[k], memory.unified_memory[k]);
            //         showing_data = 1;
            //     end else if (showing_data) begin
            //         $fdisplay(fmem_fileno, "@@@");
            //         showing_data = 0;
            //     end
            // end
            $fclose(fmem_fileno);
        end
    endtask // task show_final_mem_and_status
endmodule // module testbench
