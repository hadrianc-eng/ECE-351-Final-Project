`timescale 1ns/1ps

module tb_pattern_generator;

    logic [2:0] pattern_index;
    wire  [7:0] digit1_out;
    wire  [7:0] digit2_out;
    wire  [7:0] digit3_out;
    wire  [7:0] digit4_out;

    // Place the actual selector circuit inside the simulation.
    pattern_generator dut
    (
        .pattern_index(pattern_index),
        .digit1_out(digit1_out),
        .digit2_out(digit2_out),
        .digit3_out(digit3_out),
        .digit4_out(digit4_out)
    );

    // Set one index and check all four output bytes in position order.
    task automatic check_pattern
    (
        input logic [2:0] index_to_test,
        input logic [31:0] expected_pattern
    );
    begin
        pattern_index = index_to_test; //apply index
        #1; // Let combinational outputs settle for one simulated ns.
        //joining output bytes
        if ({digit1_out, digit2_out, digit3_out, digit4_out}
            !== expected_pattern)
        begin
            $fatal(1, "FAIL index=%0d: expected %08h, got %08h",
                index_to_test, expected_pattern,
                {digit1_out, digit2_out, digit3_out, digit4_out});
        end

        $display("PASS index=%0d: digit bytes=%02h %02h %02h %02h",
            index_to_test, digit1_out, digit2_out, digit3_out, digit4_out);
    end
    endtask

    initial
    begin
        $dumpfile("pattern_generator.vcd");
        $dumpvars(0, tb_pattern_generator);

        // Expected bytes are written independently of the design's constants.
        check_pattern(3'd0, 32'h3F3F3F3F); // 0000
        check_pattern(3'd1, 32'h7F7F7F7F); // 8888
        check_pattern(3'd2, 32'h065B4F66); // 1234
        check_pattern(3'd3, 32'h664F5B06); // 4321
        check_pattern(3'd4, 32'h6D7D077F); // 5678
        check_pattern(3'd5, 32'h6F3F065B); // 9012

        // Unused indices select blank patterns.
        check_pattern(3'd6, 32'h00000000);
        check_pattern(3'd7, 32'h00000000);

        // Jump back to a valid entry: selection must follow the input.
        check_pattern(3'd2, 32'h065B4F66); // 1234 again

        $display("ALL 9 PATTERN CHECKS PASSED");
        $finish;
    end

endmodule
