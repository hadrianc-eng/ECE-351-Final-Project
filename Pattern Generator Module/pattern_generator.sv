// First stage: select one of six four-digit display patterns.
// The future timing counter will supply pattern_index.
module pattern_generator
(
    input  logic [2:0] pattern_index,
    output logic [7:0] digit1_out,
    output logic [7:0] digit2_out,
    output logic [7:0] digit3_out,
    output logic [7:0] digit4_out
);

    // Named segment patterns for the readable message table.
    //  set bit lights the  segment; the decimal-point bit is zero.
    localparam logic [7:0] SEG_0 = 8'h3F;
    localparam logic [7:0] SEG_1 = 8'h06;
    localparam logic [7:0] SEG_2 = 8'h5B;
    localparam logic [7:0] SEG_3 = 8'h4F;
    localparam logic [7:0] SEG_4 = 8'h66;
    localparam logic [7:0] SEG_5 = 8'h6D;
    localparam logic [7:0] SEG_6 = 8'h7D;
    localparam logic [7:0] SEG_7 = 8'h07;
    localparam logic [7:0] SEG_8 = 8'h7F;
    localparam logic [7:0] SEG_9 = 8'h6F;

    // combined 32 bit signal
    logic [31:0] selected_pattern;

    // Combinational table; 1 index chooses 4 digit pattern
    always_comb
    begin
        case (pattern_index)
            3'd0: selected_pattern = {SEG_0, SEG_0, SEG_0, SEG_0}; // 0000
            3'd1: selected_pattern = {SEG_8, SEG_8, SEG_8, SEG_8}; // 8888
            3'd2: selected_pattern = {SEG_1, SEG_2, SEG_3, SEG_4}; // 1234
            3'd3: selected_pattern = {SEG_4, SEG_3, SEG_2, SEG_1}; // 4321
            3'd4: selected_pattern = {SEG_5, SEG_6, SEG_7, SEG_8}; // 5678
            3'd5: selected_pattern = {SEG_9, SEG_0, SEG_1, SEG_2}; // 9012
            default: selected_pattern = 32'h00000000;           // Blank
        endcase
    end

    // Connect each byte to its corresponding segment digit output.
    assign digit1_out = selected_pattern[31:24];
    assign digit2_out = selected_pattern[23:16];
    assign digit3_out = selected_pattern[15:8];
    assign digit4_out = selected_pattern[7:0];

endmodule
