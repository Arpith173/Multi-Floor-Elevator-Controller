//============================================================================
// Module: elevator_top
// Description: Top-level wrapper that instantiates the button debouncer
//              and the elevator FSM controller.  Port interface matches
//              the original monolithic module for drop-in compatibility.
//============================================================================

module elevator_top #(
    parameter DOOR_OPEN_TIME  = 24'd10_000_000,
    parameter DOOR_CLOSE_TIME = 24'd10_000_000
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        emergency,
    input  wire [4:0]  btn,              // Raw push-button inputs (floors 0-4)

    output wire [2:0]  current_floor,
    output wire        door,             // 1 = open, 0 = closed
    output wire [4:0]  floor_req,        // Floor request register (debug)
    output wire        direction,        // 1 = up, 0 = down
    output wire        priority          // 1 = floor-2 request active
);

    // Internal wires
    wire [4:0] btn_pulse;

    // -----------------------------------------------------------------------
    // Button Debouncer
    // -----------------------------------------------------------------------
    button_debouncer #(
        .NUM_BUTTONS(5)
    ) debounce_inst (
        .clk      (clk),
        .reset    (reset),
        .btn_in   (btn),
        .btn_pulse(btn_pulse)
    );

    // -----------------------------------------------------------------------
    // Elevator Controller (FSM + request management + door timing)
    // -----------------------------------------------------------------------
    elevator_controller #(
        .NUM_FLOORS     (5),
        .DOOR_OPEN_TIME (DOOR_OPEN_TIME),
        .DOOR_CLOSE_TIME(DOOR_CLOSE_TIME)
    ) ctrl (
        .clk          (clk),
        .reset        (reset),
        .emergency    (emergency),
        .btn_pulse    (btn_pulse),
        .current_floor(current_floor),
        .door         (door),
        .floor_req    (floor_req),
        .direction    (direction),
        .priority     (priority)
    );

endmodule
