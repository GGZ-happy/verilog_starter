/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename : mem.sv                                                //
//                                                                     //
// Description : This is a clock-based latency, pipelined memory with  //
//               3 buses (address in, data in, data out) and a limit   //
//               on the number of outstanding memory operations        //
//               allowed at any time.                                  //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "../test/mem.svh"

module mem (
    input           clock,                              // Memory clock
    input           reset,

    input MEM_COMMAND   proc2mem_command,               // MEM_NONE MEM_LOAD or MEM_STORE for 0th txn
    input WORD          proc2mem_data,                  // data for current store in 0th txn
    input ADDR      [`BUS_WIDTH-1:0]    proc2mem_addr,  // address for current commands

    output MEM_BLOCK    [`BUS_WIDTH-1:0]    mem2proc_data,  // Data for a load
    output ADDR         [`BUS_WIDTH-1:0]    mem2proc_addr,  // Address for returned data
    output logic        [`BUS_WIDTH-1:0]    mem2proc_valid, // Signal for finished transactions

    input int   stdout_fileno
);

    WORD unified_memory [`MEM_SIZE_IN_WORDS-1:0];

    logic       [`BUS_WIDTH-1:0] load_valid;
    ADDR        [`BUS_WIDTH-1:0] load_addr;
    MEM_BLOCK   [`BUS_WIDTH-1:0] load_data;

    ADDR        [`BUS_WIDTH-1:0] loaded_addr    [`MEM_LATENCY_IN_CYCLES+1:0];
    MEM_BLOCK   [`BUS_WIDTH-1:0] loaded_data    [`MEM_LATENCY_IN_CYCLES+1:0];
    logic       [`BUS_WIDTH-1:0] valid          [`MEM_LATENCY_IN_CYCLES+1:0];

    assign mem2proc_data    = loaded_data[0];
    assign mem2proc_addr    = loaded_addr[0];
    assign mem2proc_valid   = valid[0];

    // Implement the Memory function
    always @(negedge clock) begin
        load_valid = '0;
        load_addr  = 'x;
        load_data  = 'x;
        if (!reset) begin
            // First handle load-only ports
            for (int i = (proc2mem_command == MEM_LOAD ? 0 : 1); i<`BUS_WIDTH; ++i) begin
                // Get line address
                load_addr[i] = proc2mem_addr[i] - (proc2mem_addr[i] % `CACHE_BLOCK_SIZE_IN_WORDS);
                for (int w = 0; w<`CACHE_BLOCK_SIZE_IN_WORDS; ++w) begin
                    // Filling up the block data
                    load_data[i][w] = unified_memory[load_addr[i] + w];
                end
                load_valid[i] = `TRUE;
            end
            // Handle store from port 0
            if (proc2mem_command == MEM_STORE) begin
                if (proc2mem_addr[0] >= 0) unified_memory[proc2mem_addr[0]] = proc2mem_data;
                else $fwrite(stdout_fileno, "%c", -proc2mem_data);
            end
        end // if (!reset)

        for (int i = 0; i < `MEM_LATENCY_IN_CYCLES; i = i+1) begin
            loaded_data[i] <= loaded_data[i+1];
            loaded_addr[i] <= loaded_addr[i+1];
            valid[i]       <= valid[i+1];
        end

        loaded_data[`MEM_LATENCY_IN_CYCLES] <= load_data;
        loaded_addr[`MEM_LATENCY_IN_CYCLES] <= load_addr;
        valid[`MEM_LATENCY_IN_CYCLES]       <= load_valid;
    end // always @(negedge clock)

    // Initialise the entire memory
    initial begin
        // This posedge is very important, it ensures that we don't enter a race
        // condition with the negedge driven block above.
        @(posedge clock);
        for (int i = 0; i < `MEM_SIZE_IN_WORDS; i = i+1) begin
            unified_memory[i] = {$bits(WORD){1'b0}};
        end
        for (int i = 1; i <= `MEM_LATENCY_IN_CYCLES; i = i+1) begin
            loaded_data[i] = 'x;
            loaded_addr[i] = 'x;
            valid[i]       = '0;
        end
    end

endmodule // module mem
