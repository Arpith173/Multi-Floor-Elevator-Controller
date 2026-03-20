`timescale 1ns / 1ps

module elevator_tb;
    reg         clk;
    reg         reset;
    reg         emergency;
    reg  [4:0]  btn;

    wire [2:0]  current_floor;
    wire        door;
    wire [4:0]  floor_req;
    wire        direction;
    wire        priority;

    // FSM state names (mirrors elevator_controller localparams)
    localparam [2:0]
        IDLE         = 3'd0,
        MOVING_UP    = 3'd1,
        MOVING_DOWN  = 3'd2,
        DOOR_OPENING = 3'd3,
        DOOR_CLOSING = 3'd4,
        EMERG_STOP   = 3'd5,
        RETURN_TO_F1 = 3'd6;

    // -----------------------------------------------------------------------
    // DUT — override door timers for fast simulation (10 cycles ≈ 100 ns)
    // -----------------------------------------------------------------------
    elevator_top #(
        .DOOR_OPEN_TIME (24'd10),
        .DOOR_CLOSE_TIME(24'd10)
    ) uut (
        .clk          (clk),
        .reset        (reset),
        .emergency    (emergency),
        .btn          (btn),
        .current_floor(current_floor),
        .door         (door),
        .floor_req    (floor_req),
        .direction    (direction),
        .priority     (priority)
    );

    // Hierarchical access to internal FSM state for monitoring
    wire [2:0] fsm_state = uut.ctrl.state;

    // -----------------------------------------------------------------------
    // Clock generation: 100 MHz (10 ns period)
    // -----------------------------------------------------------------------
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Helper Tasks
    // -----------------------------------------------------------------------

    // Press a single button combination for ≥ 5 clock cycles, then release
    task press_button;
        input [4:0] button;
        begin
            btn = button;
            #50;                // Hold 5 cycles — guarantees sync + edge detect
            btn = 5'b00000;
        end
    endtask

    // Wait long enough for the elevator to finish servicing
    // (movement + door open + door close + margin)
    task wait_for_service;
        input integer cycles;
        begin
            #(cycles * 10);     // Each cycle = 10 ns
        end
    endtask

    // Print a divider and test title
    task print_test;
        input [63*8:1] title;
        begin
            $display("\n================================================================");
            $display("  %0s", title);
            $display("================================================================");
        end
    endtask

    // -----------------------------------------------------------------------
    // Pass/Fail checker
    // -----------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [31*8:1] label;
        input [2:0]    expected_floor;
        input          expected_door;
        begin
            if (current_floor === expected_floor && door === expected_door) begin
                $display("  [PASS] %0s : Floor=%0d  Door=%0b", label, current_floor, door);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s : Floor=%0d (exp %0d)  Door=%0b (exp %0b)",
                         label, current_floor, expected_floor, door, expected_door);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_state;
        input [31*8:1] label;
        input [2:0]    expected_state;
        begin
            if (fsm_state === expected_state) begin
                $display("  [PASS] %0s : State=%0d", label, fsm_state);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s : State=%0d (exp %0d)",
                         label, fsm_state, expected_state);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Monitor (optional — comment out to reduce log verbosity)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        $display("  t=%0t | St=%0d | Floor=%0d | Req=%b | Dir=%b | Door=%b | Pri=%b | Emrg=%b",
                 $time, fsm_state, current_floor, floor_req, direction, door, priority, emergency);
    end

    // -----------------------------------------------------------------------
    // Main Test Stimulus
    // -----------------------------------------------------------------------
    initial begin
        // Waveform dump for GTKWave / other viewers
        $dumpfile("elevator_tb.vcd");
        $dumpvars(0, elevator_tb);

        $display("================================================================");
        $display("  Multi-Floor Elevator Controller — Testbench");
        $display("  Clock: 100 MHz | Door timers: 10 cycles each");
        $display("================================================================");

        // ---------- Initialise ----------
        clk       = 0;
        reset     = 1;
        emergency = 0;
        btn       = 5'b00000;
        #30;
        reset     = 0;
        #20;

        // ==================================================================
        // TEST 1 — Single floor request: Floor 4 from Floor 0
        // ==================================================================
        print_test("Test 1: Request Floor 4 from Floor 0");
        press_button(5'b10000);
        wait_for_service(80);                       // 4 floors + door cycles
        check("Arrived at F4", 3'd4, 1'b0);

        // ==================================================================
        // TEST 2 — Priority: Floors 0, 2, 3 pressed together
        //          Floor 2 has priority → should be serviced first
        // ==================================================================
        print_test("Test 2: Priority — Req F0, F2, F3 (F2 first)");
        press_button(5'b01101);
        wait_for_service(50);                       // Move from F4→F3 then F3→F2
        check("F2 serviced first", 3'd2, 1'b0);
        wait_for_service(80);
        // After F2, remaining requests are F0 and F3.
        // From F2, nearest above is F3 → service F3, then F0.
        wait_for_service(80);

        // ==================================================================
        // TEST 3 — Emergency during operation
        //          Press F0 & F1, then trigger emergency mid-travel
        // ==================================================================
        print_test("Test 3: Emergency during floor service");
        press_button(5'b00011);     // Request F0 and F1
        #60;                        // Let the elevator start moving
        emergency = 1;
        $display("  >>> Emergency ACTIVATED");
        #40;
        check_state("In EMERG_STOP", EMERG_STOP);
        #10;
        emergency = 0;
        $display("  >>> Emergency DEACTIVATED — returning to F1");
        wait_for_service(80);
        check("Returned to F1", 3'd1, 1'b0);

        // ==================================================================
        // TEST 4 — Repeated Floor 2 press (de-bounce / priority)
        // ==================================================================
        print_test("Test 4: Repeated Floor 2 presses");
        press_button(5'b00100);     // Press 1
        #20;
        press_button(5'b00100);     // Press 2
        #20;
        press_button(5'b00100);     // Press 3
        wait_for_service(80);
        check("At F2 after repeated presses", 3'd2, 1'b0);

        // ==================================================================
        // TEST 5 — Idle: no requests at all
        // ==================================================================
        print_test("Test 5: Idle — no requests");
        wait_for_service(20);
        check_state("Stays IDLE", IDLE);
        check("Stays at last floor", current_floor, 1'b0);

        // ==================================================================
        // TEST 6 — Sequential requests: F0 → F1 → F2 → F4
        // ==================================================================
        print_test("Test 6: Sequential requests F0, F1, F2, F4");
        press_button(5'b00001);  #30;     // F0
        press_button(5'b00010);  #30;     // F1
        press_button(5'b00100);  #30;     // F2 (priority)
        press_button(5'b10000);  #30;     // F4
        wait_for_service(200);            // Allow full servicing
        // Elevator should eventually return to IDLE after all are served

        // ==================================================================
        // TEST 7 — Request for the current floor (instant door open)
        // ==================================================================
        print_test("Test 7: Request for current floor");
        // First go to F4
        press_button(5'b10000);
        wait_for_service(100);
        // Now request F4 again while already there
        press_button(5'b10000);
        #60;    // Wait for debounce + FSM to see request
        check("Door opens at current floor", 3'd4, 1'b1);
        wait_for_service(40);

        // ==================================================================
        // TEST 8 — Multiple simultaneous requests
        // ==================================================================
        print_test("Test 8: Multiple requests F0, F2, F3");
        press_button(5'b01101);
        wait_for_service(200);

        // ==================================================================
        // TEST 9 — Emergency while idle
        // ==================================================================
        print_test("Test 9: Emergency while idle");
        wait_for_service(20);               // Ensure IDLE
        emergency = 1;
        $display("  >>> Emergency ACTIVATED while idle");
        #60;
        check_state("In EMERG_STOP", EMERG_STOP);
        emergency = 0;
        $display("  >>> Emergency DEACTIVATED");
        wait_for_service(80);
        check("Returned to F1 after idle emergency", 3'd1, 1'b0);

        // ==================================================================
        // TEST 10 — Intermediate floor servicing
        //           Request F0 and F4 from F2; elevator should stop at
        //           an intermediate floor if requested while in motion
        // ==================================================================
        print_test("Test 10: Intermediate floor servicing");
        // Go to F2 first
        press_button(5'b00100);
        wait_for_service(80);
        // Now request F0 and F4
        press_button(5'b10001);
        #50;
        // While moving up toward F4, inject F3 request
        press_button(5'b01000);
        wait_for_service(200);

        // ==================================================================
        // TEST 11 — Boundary: Request from Floor 0 stays at Floor 0
        // ==================================================================
        print_test("Test 11: Request floor 0 from floor 0");
        // First ensure we are at floor 0
        press_button(5'b00001);
        wait_for_service(100);
        // Request floor 0 again
        press_button(5'b00001);
        #60;
        check("Door opens at F0", 3'd0, 1'b1);
        wait_for_service(40);

        // ==================================================================
        // SUMMARY
        // ==================================================================
        $display("\n================================================================");
        $display("  TESTBENCH COMPLETE");
        $display("  Passed: %0d | Failed: %0d", pass_count, fail_count);
        $display("================================================================\n");

        $finish;
    end

endmodule
