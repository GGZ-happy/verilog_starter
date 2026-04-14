// Direct-mapped icache

`include "sys_defs.svh"

module icache #(
    parameter NUM_LINES = 16
)(
    input clock,
    input reset,

    input ADDR if_addr, // addr from IF stage

    // fetch data
    output ADDR ic_addr,
    output MEM_BLOCK  ic_data,
    output logic ic_valid,

    // read data from mem
    output ADDR ic2mem_addr,

    input logic mem_valid,
    input MEM_BLOCK mem_data,
    input ADDR mem_addr
);

localparam block_off_bits = `CACHE_BLOCK_OFFSET_BITS;
localparam line_idx_bits = $clog2(NUM_LINES);
localparam tag_bits = $bits(ADDR) - line_idx_bits - block_off_bits;

// cache structure
logic [NUM_LINES-1 : 0]  cache_valid;
logic [tag_bits-1:0]    cache_tag   [NUM_LINES-1 : 0];
MEM_BLOCK               cache_data  [NUM_LINES-1 : 0];

logic [line_idx_bits-1:0] find_idx;
logic [tag_bits-1:0] find_tag;
assign find_idx = if_addr[block_off_bits +: line_idx_bits];
assign find_tag = if_addr[block_off_bits+line_idx_bits +: tag_bits];

logic cache_hit;
assign cache_hit = cache_valid[find_idx] && cache_tag[find_idx] == find_tag;

// fetch from mem if not match
logic mem_response_match;
ADDR find_addr;
assign find_addr = {find_tag, find_idx, `CACHE_BLOCK_OFFSET_BITS'b0};
assign mem_response_match = mem_valid && mem_addr == find_addr;
assign ic2mem_addr = find_addr;

// Final output
assign ic_valid = mem_response_match || cache_hit;
assign ic_addr = find_addr;
assign ic_data = cache_hit? cache_data[find_idx]:
            mem_response_match? mem_data : '0;

// Write cache
logic [line_idx_bits-1:0] fill_idx;
logic [tag_bits-1:0] fill_tag;
assign fill_idx = mem_addr[block_off_bits +: line_idx_bits];
assign fill_tag = mem_addr[block_off_bits + line_idx_bits +: tag_bits];
always_ff @(posedge clock) begin
    if (reset) begin
        cache_valid <= '0;
    end else if (mem_valid) begin
        cache_valid[fill_idx] <= 1'b1;
        cache_tag[fill_idx] <= fill_tag;
        cache_data[fill_idx] <= mem_data;
    end

end
endmodule