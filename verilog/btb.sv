`include "sys_defs.svh"

module btb #(
    parameter NUM_ENTRIES = `BTB_ENTRIES,
    parameter NUM_BANKS = `BANKS
)(
    input clock,
    input reset,

    // look up pc in IF stage
    input ADDR      [3:0] lookup_pc,
    output logic    [3:0] hit,
    output ADDR     [3:0] target,

    // Update PC in WB stage
    input logic     [1:0] update_en,
    input ADDR      [1:0] update_pc,
    input ADDR      [1:0] update_target
);

localparam line_idx = $clog2(NUM_ENTRIES);
localparam bank_idx = $clog2(NUM_BANKS);
localparam tag_bits = $bits(ADDR) - bank_idx - line_idx ;

// btb structure
logic [NUM_ENTRIES-1:0] btb_valid [NUM_BANKS-1:0];
logic [tag_bits-1:0]    btb_tag[NUM_BANKS-1:0][NUM_ENTRIES-1:0];
logic [$bits(ADDR)-1:0] btb_target [NUM_BANKS-1:0][NUM_ENTRIES-1:0];

// Find four port simultaneously
genvar j;
generate
for (j = 0; j < 4; j++) begin : lookup
    logic bank;
    logic [line_idx-1:0] idx;
    logic [tag_bits-1:0] tag;
    assign bank = lookup_pc[j][bank_idx-1:0];
    assign idx = lookup_pc[j][bank_idx +:line_idx];
    assign tag = lookup_pc[j][line_idx + bank_idx +: tag_bits];
    assign hit[j] = btb_valid[bank][idx] && btb_tag[bank][idx] == tag;
    assign target[j] = btb_target[bank][idx];
end
endgenerate

logic [1:0]   update_bank;
logic [line_idx-1:0]    update_idx [1:0];
logic [tag_bits-1:0]    update_tag [1:0];
generate
for (j = 0; j < 2; j++) begin : update
    assign update_bank[j] = update_pc[j][bank_idx-1:0];
    assign update_idx[j] = update_pc[j][bank_idx +: line_idx];
    assign update_tag[j] = update_pc[j][line_idx + bank_idx +: tag_bits];
end
endgenerate

always_ff @(posedge clock) begin
    if (reset) begin
        btb_valid[0] <= '0;
        btb_valid[1] <= '0;
    end else begin
        if (update_en[0]) begin
            btb_valid[update_bank[0]][update_idx[0]] <= 1'b1;
            btb_tag[update_bank[0]][update_idx[0]] <= update_tag[0];
            btb_target[update_bank[0]][update_idx[0]] <= update_target[0];
        end 
        if (update_en[1]) begin
            btb_valid[update_bank[1]][update_idx[1]] <= 1'b1;
            btb_tag[update_bank[1]][update_idx[1]] <= update_tag[1];
            btb_target[update_bank[1]][update_idx[1]] <= update_target[1];
        end
    end
end 
endmodule