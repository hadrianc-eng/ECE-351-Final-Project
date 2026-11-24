// Terminal Compile Command: iverilog -g2012 -Wall -s tb_tm1637_full -o sim.vvp tm1637_byte_full.sv tb_tm1637_byte_controller.sv

module tm1637_byte_controller (
    input  logic       clk,
    input  logic       reset,
    input  logic       send,
    
    //input  logic [7:0] byte_in,	// unused
    
    //++
    input logic [7:0] digit1_in,  // Pattern for first digit
    input logic [7:0] digit2_in,  // Pattern for second digit
    input logic [7:0] digit3_in,  // Pattern for third digit
    input logic [7:0] digit4_in,  // Pattern for fourth digit

    output logic       tm_clk,
    inout  wire        tm_dio,

    output logic       busy,
    output logic       done,
    output logic       error
);

    // ----------------------------------------
    // Datapath registers and status
    // ----------------------------------------

    logic [7:0] data_reg;
    logic [2:0] bit_counter;
    logic [7:0] timer_count;
    logic [2:0] byte_counter;
    logic [1:0] transaction_counter;

	// Datapath status signals -> FSM
	logic last_transaction;
    logic last_bit;
    logic timer_done;
    logic last_byte;

    // FSM -> datapath control signals
    logic transaction_enable;
	logic transaction_reset;
	logic byte_enable;
	logic byte_reset;
    logic load_byte;
    logic bit_reset;
    logic bit_enable;
    logic timer_reset;
    logic timer_enable;
  
    // ACK detection and error-status - Captures ACK from TM1637 - Datapath Subsystem 
    logic ack_clear;
    logic ack_sample;
    logic ack_ok;
    logic error_clear;
    logic transaction_error;

	
	// Datapath internal signals
	logic tx_bit;
	logic [7:0] selected_byte;
	

    // DIO output control    
    logic dio_drive_low;
    

    // Open-drain-style interface
    
    assign tm_dio = dio_drive_low ? 1'b0 : 1'bz;

    // ----------------------------------------
    // Transmission register
    // ----------------------------------------

    always_ff @(posedge clk) begin
        if (reset)
            data_reg <= 8'h00;
        else if (load_byte)
            data_reg <= selected_byte;
    end

    // ----------------------------------------
    // Bit counter
    // ----------------------------------------

    always_ff @(posedge clk) begin
        if (reset || bit_reset)
            bit_counter <= 3'd0;
        else if (bit_enable)
            bit_counter <= bit_counter + 3'd1;
    end

    assign tx_bit   = data_reg[bit_counter];
    assign last_bit = (bit_counter == 3'd7);
    
    
	// ----------------------------------------
    // Byte counter
    // ----------------------------------------
	always_ff @(posedge clk) begin
		if (reset || byte_reset)
			byte_counter <= 3'd0;
		else if (byte_enable)
			byte_counter <= byte_counter + 3'd1;
	end
	
	assign last_byte =
		(transaction_counter == 2'd1)
			? (byte_counter == 3'd4)
			: (byte_counter == 3'd0);

	// ----------------------------------------
    // Transaction counter
    // ----------------------------------------
    
	always_ff @(posedge clk) begin
		if (reset || transaction_reset)
			transaction_counter <= 2'd0;
		else if (transaction_enable)
			transaction_counter <= transaction_counter + 2'd1;
	end
	
	assign last_transaction = (transaction_counter == 2'd2);


    // ----------------------------------------
    // Timing counter
    // 27 MHz / 100 kHz / 2 = 135 cycles
    // ----------------------------------------

    always_ff @(posedge clk) begin
        if (reset || timer_reset)
            timer_count <= 8'd0;
        else if (timer_enable && !timer_done)
            timer_count <= timer_count + 8'd1;
    end

    assign timer_done = (timer_count == 8'd134);

    // ----------------------------------------
    // ACK capture register
    // ----------------------------------------

    always_ff @(posedge clk) begin
        if (reset || ack_clear)
            ack_ok <= 1'b0;
        else if (ack_sample)
            ack_ok <= ~tm_dio;
    end
    
    // ----------------------------------------
    // ACK byte acknowledgement 
    // ----------------------------------------
    
    always_ff @(posedge clk) begin
		if (reset || error_clear)
			transaction_error <= 1'b0;
		else if (ack_sample && tm_dio)
			transaction_error <= 1'b1;
	end
    
  
    // ----------------------------------------
    // FSM state definitions
    // ----------------------------------------

    typedef enum logic [5:0] {
        IDLE,				// 0 
        START_SETUP,		// 1
        START_ASSERT,		// 2
        START_CLOCK,		// 3
        LOAD_BYTE,			// 4
        BIT_LOW,			// 5
        BIT_HIGH,			// 6
        BIT_FALL,			// 7
        BIT_ADVANCE,		// 8
        ACK_LOW,			// 9
        ACK_HIGH,			// 10 0xA
        ACK_FINISH,			// 11 0xB
        CHECK_ACK,			// 12 0xC
        NEXT_BYTE,			// 13 0xD
        STOP_LOW,			// 14 0xE
        STOP_HIGH,			// 15 0xF
        STOP_RELEASE,		// 16 0x10
        CHECK_TRANSACTION,	// 17 0x11
        NEXT_TRANSACTION,	// 18 0x12
        DONE_STATE      	// 19 0x13
    } state_t;

    state_t state, next_state;

    // ----------------------------------------
    // State register
    // ----------------------------------------

    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ----------------------------------------
    // Next-state logic
    // ----------------------------------------

    always_comb begin

        next_state = state;

        case (state)

            IDLE:
                if (send)
                    next_state = START_SETUP;

			// START
            START_SETUP:
                if (timer_done)
                    next_state = START_ASSERT;

            START_ASSERT:
                if (timer_done)
                    next_state = START_CLOCK;

            START_CLOCK:
                if (timer_done)
                    next_state = LOAD_BYTE;
            
            // TRANSMIT    
            LOAD_BYTE:
				next_state = BIT_LOW;

			
            BIT_LOW:
                if (timer_done)
                    next_state = BIT_HIGH;

            BIT_HIGH:
                if (timer_done)
                    next_state = BIT_FALL;

            BIT_FALL:
                if (last_bit)
                    next_state = ACK_LOW;
                else
                    next_state = BIT_ADVANCE;

            BIT_ADVANCE:
                next_state = BIT_LOW;
			
			// ACKNOWLEDGE
            ACK_LOW:
                if (timer_done)
                    next_state = ACK_HIGH;

            ACK_HIGH:
                if (timer_done)
                    next_state = ACK_FINISH;

            ACK_FINISH:
                if (timer_done)
                    next_state = CHECK_ACK;
            
            CHECK_ACK:
				if (!ack_ok)
					next_state = STOP_LOW;
				else if (last_byte)
					next_state = STOP_LOW;
				else
					next_state = NEXT_BYTE;
            
            NEXT_BYTE:
				next_state = LOAD_BYTE;
			
			// STOP
			
            STOP_LOW:
                if (timer_done)
                    next_state = STOP_HIGH;

            STOP_HIGH:
                if (timer_done)
                    next_state = STOP_RELEASE;

            STOP_RELEASE:
                if (timer_done)
                    next_state = CHECK_TRANSACTION;
              
              
            // CHECK TRANSACTION      
            CHECK_TRANSACTION: begin
				if (transaction_error)
					next_state = DONE_STATE;
                else if (last_transaction)
					next_state = DONE_STATE;
				else
					next_state = NEXT_TRANSACTION;
			end
					
			NEXT_TRANSACTION:
				next_state = START_SETUP;
            
            DONE_STATE:
                next_state = IDLE;

            default:
                next_state = IDLE;

        endcase
    end

	// ----------------------------------------
    // Byte selector logic
    // ----------------------------------------


	always_comb begin
		selected_byte = 8'h00;
	
		case (transaction_counter)
	
			// Transaction 0: Data command
			2'd0: begin
				selected_byte = 8'h40;
			end
	
	
			// Transaction 1: Address + four digits
			2'd1: begin
				case (byte_counter)
					3'd0: selected_byte = 8'hC0; 
					3'd1: selected_byte = digit1_in;
					3'd2: selected_byte = digit2_in;
					3'd3: selected_byte = digit3_in;
					3'd4: selected_byte = digit4_in;
					default: selected_byte = 8'h00;
				endcase
			end
			
			// Transaction 2: Display ON
			2'd2: begin
				selected_byte = 8'h8F;
			end
			
			default: selected_byte = 8'h00;
			
		endcase
	end

    // ----------------------------------------
    // FSM output logic
    // ----------------------------------------

    always_comb begin

        // Default datapath controls
        load_byte    = 1'b0;
        bit_reset    = 1'b0;
        bit_enable   = 1'b0;
        byte_enable  = 1'b0;
        byte_reset   = 1'b0;

        timer_enable = 1'b0;
        timer_reset  = 1'b0;

        ack_clear    = 1'b0;
        ack_sample   = 1'b0;

        // Default status outputs
        busy 			   = 1'b1;
        done  			   = 1'b0;
        error 			   = 1'b0;
        error_clear 	   = 1'b0;
        transaction_enable = 1'b0;
        transaction_reset  = 1'b0;

        case (state)

            IDLE: begin
                busy        = 1'b0;
                timer_reset = 1'b1;

                if (send) begin
					transaction_reset = 1'b1;
                    byte_reset 		  = 1'b1;
                    bit_reset 		  = 1'b1;
                    ack_clear 		  = 1'b1;
                    error_clear 	  = 1'b1;
                end
            end

            START_SETUP: begin         
                timer_enable = 1'b1;
            end

            START_ASSERT: begin
                timer_enable = 1'b1;
            end

            START_CLOCK: begin
                timer_enable = 1'b1;
            end
            
            LOAD_BYTE: begin
				bit_reset  = 1'b1;
				load_byte  = 1'b1;
				timer_reset = 1'b1;
            end
            
            BIT_LOW: begin
                timer_enable = 1'b1;
            end

            BIT_HIGH: begin
                timer_enable = 1'b1;
            end

            BIT_FALL: begin
                timer_reset = 1'b1;
            end

            BIT_ADVANCE: begin
                bit_enable = 1'b1;
                timer_reset = 1'b1;
            end

            ACK_LOW: begin
                timer_enable = 1'b1;
            end

            ACK_HIGH: begin
                timer_enable = 1'b1;

                if (timer_done)
                    ack_sample = 1'b1;
            end

            ACK_FINISH: begin
                timer_enable = 1'b1;
            end
            
            
            NEXT_BYTE: begin
				byte_enable = 1'b1;
				timer_reset = 1'b1;
            end

            STOP_LOW: begin
                timer_enable = 1'b1;
            end

            STOP_HIGH: begin
                timer_enable = 1'b1;
            end

            STOP_RELEASE: begin
                timer_enable = 1'b1;
            end
            
            NEXT_TRANSACTION: begin
				transaction_enable = 1'b1;
				byte_reset		   = 1'b1;
                bit_reset		   = 1'b1;
                timer_reset		   = 1'b1;
            end

            DONE_STATE: begin
                busy  = 1'b0;
                done  = 1'b1;
                error = transaction_error;
                timer_reset = 1'b1;
            end

            default: begin
                timer_reset = 1'b1;
            end
            
            endcase
            
            // Restart timer on completion of timed state.
			if (timer_enable && timer_done)
				timer_reset = 1'b1;
			end
            
			// TM1637 clock output
			assign tm_clk =
			(state == IDLE)          	 ||
			(state == START_SETUP)   	 ||
			(state == START_ASSERT)  	 ||
			(state == BIT_HIGH)      	 ||
			(state == ACK_HIGH)      	 ||
			(state == STOP_HIGH)     	 ||
			(state == STOP_RELEASE)  	 ||
			(state == CHECK_TRANSACTION) ||
			(state == NEXT_TRANSACTION)	 ||
			(state == DONE_STATE);


			// TM1637 data output control
			assign dio_drive_low =
			(state == START_ASSERT)  ||
			(state == LOAD_BYTE)	 ||
			(state == START_CLOCK)   ||
			(state == STOP_LOW)      ||
			(state == STOP_HIGH)     ||

			// Drive the selected data bit
			(
				(
					(state == BIT_LOW)     ||
					(state == BIT_HIGH)    ||
					(state == BIT_FALL)    ||
					(state == BIT_ADVANCE)
				)
				&& !tx_bit
			);

       

endmodule
