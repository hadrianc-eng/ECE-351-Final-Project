
`timescale 1ns/1ps

module tb_tm1637_full;

    logic clk = 0;
    logic reset = 1;
    logic send = 0;
    //logic [7:0] byte_in = 0;
	//++
    logic [2:0] pattern_index = 3'd0;
    wire [7:0] digit1, digit2, digit3, digit4;

    logic tm_clk;
    tri1 tm_dio;

    logic busy, done, error;

    // Simulated TM1637 open-drain driver
    logic slave_drive_low = 0;

    // -1: ACK all bytes
    //  0 through 6: NACK selected byte
    integer nack_index = -1;

    // Protocol monitor
    logic active = 0;
    integer start_count = 0;
    integer stop_count = 0;
    integer stop_clocks = 0;
    integer bytes_seen = 0;
    integer serial_clocks = 0;
    integer bit_index = 0;

    logic [7:0] received_byte = 0;

    // Approximately 27 MHz system clock
    always #18.5185 clk = ~clk;
    //select the 4 digit code
    pattern_generator patterns (
        .pattern_index(pattern_index),
        .digit1_out(digit1),
        .digit2_out(digit2),
        .digit3_out(digit3),
        .digit4_out(digit4)
    );
    // Device under test
  	//++
    tm1637_byte_controller dut (
        .clk(clk),
        .reset(reset),
        .send(send),
        .digit1_in(digit1),
      	.digit2_in(digit2),
      	.digit3_in(digit3),
      	.digit4_in(digit4),
        .tm_clk(tm_clk),
        .tm_dio(tm_dio),
        .busy(busy),
        .done(done),
        .error(error)
    );

    assign tm_dio =
        slave_drive_low ? 1'b0 : 1'bz;

    // -----------------------------------------
    // Expected transmission bytes
    // -----------------------------------------

    function automatic [7:0] expected_byte(
        input integer index
    );
        case (index)
            0: expected_byte = 8'h40;
            1: expected_byte = 8'hC0;
          
            2: expected_byte = digit1;
            3: expected_byte = digit2;
            4: expected_byte = digit3;
            5: expected_byte = digit4;
            6: expected_byte = 8'h8F;
            default: expected_byte = 8'hXX;
        endcase
    endfunction

    // -----------------------------------------
    // START detection
    // -----------------------------------------

    always @(negedge tm_dio) begin
        if (reset === 1'b0 &&
            tm_clk === 1'b1) begin

            if (active)
                $fatal(1, "Unexpected repeated START");

            active = 1;
            bit_index = 0;
            received_byte = 0;
            start_count = start_count + 1;

            $display("[%0t] START %0d",
                     $time, start_count);
        end
    end

    // -----------------------------------------
    // STOP detection
    // -----------------------------------------

    always @(posedge tm_dio) begin
        if (active && tm_clk === 1'b1) begin

            active = 0;
            stop_count = stop_count + 1;

            if (bit_index != 0)
                $fatal(1,
                    "STOP during incomplete byte");

            $display("[%0t] STOP %0d",
                     $time, stop_count);
        end
    end

    // -----------------------------------------
    // Receive bits and verify ACK
    // -----------------------------------------

    always @(posedge tm_clk) begin

        // Allow FSM outputs to settle
        #1;

        if (active) begin

            // STOP preparation raises CLK, but
            // is not another serial data clock.
            if (dut.state == dut.STOP_HIGH) begin

                stop_clocks = stop_clocks + 1;

            end else begin

                serial_clocks = serial_clocks + 1;

                if (bytes_seen >= 7)
                    $fatal(1,
                        "Too many bytes transmitted");

                if (bit_index < 8) begin

                    received_byte[bit_index] = tm_dio;
                    bit_index = bit_index + 1;

                end else begin

                    // Ninth clock: ACK or NACK
                    if (received_byte !==
                        expected_byte(bytes_seen))
                        $fatal(1,
                            "Byte %0d mismatch: expected %02h, got %02h",
                            bytes_seen,
                            expected_byte(bytes_seen),
                            received_byte);

                    if (bytes_seen == nack_index) begin

                        if (tm_dio !== 1'b1)
                            $fatal(1,
                                "Expected NACK on byte %0d",
                                bytes_seen);

                    end else begin

                        if (tm_dio !== 1'b0)
                            $fatal(1,
                                "Expected ACK on byte %0d",
                                bytes_seen);

                    end

                    $display(
                        "Byte %0d: %02h, response=%s",
                        bytes_seen,
                        received_byte,
                        (bytes_seen == nack_index)
                            ? "NACK" : "ACK"
                    );

                    bytes_seen = bytes_seen + 1;
                    bit_index = 0;
                    received_byte = 0;

                end
            end
        end
    end

    // -----------------------------------------
    // Simulated TM1637 ACK response
    // -----------------------------------------

    always @(negedge tm_clk) begin

        // Wait for state and clock monitor
        // to settle before updating DIO.
        #1;

        if (active) begin

            // Eighth data clock completed:
            // assert ACK before ninth rising edge.
            if (bit_index == 8) begin

                slave_drive_low =
                    (bytes_seen != nack_index);

            end else if (bit_index == 0) begin

                // Ninth clock completed:
                // release acknowledgment.
                slave_drive_low = 0;

            end
        end

    end

    // -----------------------------------------
    // Execute and check one display update
    // -----------------------------------------

    task automatic run_test(
        input integer test_nack,
        input integer expected_count,
        input integer expected_transactions
    );

        begin

            nack_index = test_nack;

            // Reset monitor between tests
            start_count = 0;
            stop_count = 0;
            stop_clocks = 0;
            bytes_seen = 0;
            serial_clocks = 0;
            bit_index = 0;
            received_byte = 0;
            slave_drive_low = 0;

            @(negedge clk);
            send = 1;

            @(negedge clk);
            send = 0;

            @(posedge done);
            #1;

            if (bytes_seen != expected_count)
                $fatal(1,
                    "Expected %0d bytes, got %0d",
                    expected_count, bytes_seen);

            if (serial_clocks != expected_count * 9)
                $fatal(1,
                    "Serial clock count incorrect: %0d",
                    serial_clocks);

            if (start_count != expected_transactions)
                $fatal(1,
                    "Expected %0d STARTs, got %0d",
                    expected_transactions, start_count);

            if (stop_count != expected_transactions)
                $fatal(1,
                    "Expected %0d STOPs, got %0d",
                    expected_transactions, stop_count);

            if (stop_clocks != expected_transactions)
                $fatal(1,
                    "Expected %0d STOP clock transitions, got %0d",
                    expected_transactions, stop_clocks);

            if (active)
                $fatal(1, "Transaction still active");

            if (test_nack == -1 && error)
                $fatal(1, "Unexpected error flag");

            if (test_nack != -1 && !error)
                $fatal(1, "Missing error flag");

            $display(
                "PASS: %0d bytes, %0d transactions, error=%b",
                bytes_seen, start_count, error
            );

            // Return to IDLE before next request
            repeat (4) @(negedge clk);

        end
    endtask

    // -----------------------------------------
    // Main simulation
    // -----------------------------------------

    initial begin
    //++
    // Record signals so we can inspect their waveforms.
    $dumpfile("tm1637_full.vcd");
    $dumpvars(0, tb_tm1637_full);

    // Give the controller time to reset, then release reset.
    repeat (3) @(negedge clk);
    reset = 0;
    //++
    // Select 4321, then transmit and check it.
    pattern_index = 3'd3;
    $display("\nTEST 1: Generated pattern 4321");
    run_test(-1, 7, 3);

    // Select 1234 after the previous transmission finishes.
    pattern_index = 3'd2;
    $display("\nTEST 2: Generated pattern 1234");
    run_test(-1, 7, 3);

    // Check that a rejected data byte causes an early stop.
    $display("\nTEST 3: NACK display byte 3");
    run_test(3, 4, 2);

    // Check that a rejected first command also stops the update.
    $display("\nTEST 4: NACK first command");
    run_test(0, 1, 1);

    $display("\nALL TESTS PASSED!");
        $finish;

    end

    // Watchdog timeout
    initial begin
        #4000000;
        $fatal(1, "Simulation timeout");
    end

endmodule
