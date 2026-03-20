module elevator_controller #(
    parameter NUM_FLOORS      = 5,
    parameter DOOR_OPEN_TIME  = 24'd10_000_000,  // ~0.1s at 100 MHz
    parameter DOOR_CLOSE_TIME = 24'd10_000_000
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire                    emergency,
    input  wire [NUM_FLOORS-1:0]   btn_pulse,      // Debounced rising-edge pulses

    output reg  [2:0]              current_floor,
    output reg                     door,            // 1 = open, 0 = closed
    output reg  [NUM_FLOORS-1:0]   floor_req,       // Active request register
    output reg                     direction,       // 1 = up, 0 = down
    output wire                    priority         // 1 = floor 2 request active
);

    // -----------------------------------------------------------------------
    // FSM State Encoding
    // -----------------------------------------------------------------------
    localparam [2:0]
        IDLE         = 3'd0,
        MOVING_UP    = 3'd1,
        MOVING_DOWN  = 3'd2,
        DOOR_OPENING = 3'd3,
        DOOR_CLOSING = 3'd4,
        EMERG_STOP   = 3'd5,
        RETURN_TO_F1 = 3'd6;

    reg [2:0] state, next_state;
    reg [2:0] target_floor, next_target_floor;
    reg       next_direction;
    reg       post_emergency;       // Flag: need to return to floor 1
    reg [23:0] door_timer;
    integer i;

    // -----------------------------------------------------------------------
    // Priority Output — floor 2 request is flagged
    // -----------------------------------------------------------------------
    assign priority = floor_req[2];

    // -----------------------------------------------------------------------
    // Request Register Logic
    //   - Latch new requests from debounced pulses
    //   - Clear current floor request when door opens
    //   - Freeze requests during EMERGENCY / RETURN_TO_F1
    //   - BUG FIX: combine latch + clear in DOOR_OPENING so new presses
    //     during door-open are not lost
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            floor_req <= {NUM_FLOORS{1'b0}};
        end else if (state != EMERG_STOP && state != RETURN_TO_F1) begin
            if (state == DOOR_OPENING)
                floor_req <= (floor_req | btn_pulse) & ~(5'b00001 << current_floor);
            else
                floor_req <= floor_req | btn_pulse;
        end
        // During EMERGENCY / RETURN_TO_F1: floor_req is unchanged
    end

    // -----------------------------------------------------------------------
    // FSM — Combinational Next-State / Output Logic
    // -----------------------------------------------------------------------
    always @* begin
        next_state        = state;
        next_target_floor = target_floor;
        next_direction    = direction;
        door              = 1'b0;

        case (state)

            // ---- EMERGENCY: doors open, wait for emergency to clear ----
            EMERG_STOP: begin
                door = 1'b1;
                if (emergency)
                    next_state = EMERG_STOP;
                else begin
                    next_state        = RETURN_TO_F1;
                    next_target_floor = 3'd1;
                end
            end

            // ---- RETURN TO FLOOR 1 after emergency ----
            RETURN_TO_F1: begin
                if (current_floor == 3'd1) begin
                    door       = 1'b1;
                    next_state = DOOR_CLOSING;
                end else begin
                    door              = 1'b0;
                    next_target_floor = 3'd1;
                    if (current_floor < 3'd1) begin
                        next_direction = 1'b1;
                        next_state     = MOVING_UP;
                    end else begin
                        next_direction = 1'b0;
                        next_state     = MOVING_DOWN;
                    end
                end
            end

            // ---- IDLE: evaluate pending requests ----
            IDLE: begin
                if (emergency) begin
                    next_state = EMERG_STOP;
                end else if (floor_req[2] && current_floor != 3'd2) begin
                    // Floor 2 has priority
                    next_target_floor = 3'd2;
                    next_direction    = (current_floor < 3'd2) ? 1'b1 : 1'b0;
                    next_state        = (current_floor < 3'd2) ? MOVING_UP : MOVING_DOWN;
                end else if (floor_req[current_floor]) begin
                    // Request for current floor — open door immediately
                    next_state = DOOR_OPENING;
                end else if (|floor_req) begin
                    // Find nearest floor above (reverse iteration: last write = lowest above)
                    next_target_floor = current_floor;
                    for (i = 4; i >= 0; i = i - 1)
                        if ((i[2:0] > current_floor) && floor_req[i])
                            next_target_floor = i[2:0];

                    if (next_target_floor != current_floor) begin
                        next_direction = 1'b1;
                        next_state     = MOVING_UP;
                    end else begin
                        // Find nearest floor below (forward iteration: last write = highest below)
                        for (i = 0; i < 5; i = i + 1)
                            if ((i[2:0] < current_floor) && floor_req[i])
                                next_target_floor = i[2:0];
                        if (next_target_floor != current_floor) begin
                            next_direction = 1'b0;
                            next_state     = MOVING_DOWN;
                        end
                    end
                end
            end

            // ---- MOVING UP: advance one floor per cycle ----
            MOVING_UP: begin
                next_direction = 1'b1;
                if (emergency) begin
                    next_state = EMERG_STOP;
                end else if (current_floor < 3'd4) begin
                    if (current_floor + 3'd1 == target_floor)
                        next_state = DOOR_OPENING;
                    else if (floor_req[current_floor + 1]) begin
                        // Service intermediate requested floor
                        next_target_floor = current_floor + 3'd1;
                        next_state        = DOOR_OPENING;
                    end else
                        next_state = MOVING_UP;
                end else
                    next_state = IDLE;  // Safety: at top floor
            end

            // ---- MOVING DOWN: advance one floor per cycle ----
            MOVING_DOWN: begin
                next_direction = 1'b0;
                if (emergency) begin
                    next_state = EMERG_STOP;
                end else if (current_floor > 3'd0) begin
                    if (current_floor - 3'd1 == target_floor)
                        next_state = DOOR_OPENING;
                    else if (floor_req[current_floor - 1]) begin
                        next_target_floor = current_floor - 3'd1;
                        next_state        = DOOR_OPENING;
                    end else
                        next_state = MOVING_DOWN;
                end else
                    next_state = IDLE;  // Safety: at bottom floor
            end

            // ---- DOOR OPENING ----
            DOOR_OPENING: begin
                door = 1'b1;
                if (emergency)
                    next_state = EMERG_STOP;
                else if (door_timer < DOOR_OPEN_TIME)
                    next_state = DOOR_OPENING;
                else
                    next_state = DOOR_CLOSING;
            end

            // ---- DOOR CLOSING ----
            DOOR_CLOSING: begin
                door = 1'b0;
                if (emergency) begin
                    next_state = EMERG_STOP;
                end else if (door_timer < DOOR_CLOSE_TIME) begin
                    next_state = DOOR_CLOSING;
                end else if (post_emergency && current_floor == 3'd1) begin
                    next_state = IDLE;
                end else if (floor_req[2] && current_floor != 3'd2) begin
                    next_target_floor = 3'd2;
                    next_direction    = (current_floor < 3'd2) ? 1'b1 : 1'b0;
                    next_state        = (current_floor < 3'd2) ? MOVING_UP : MOVING_DOWN;
                end else if (|floor_req) begin
                    next_target_floor = current_floor;
                    for (i = 4; i >= 0; i = i - 1)
                        if ((i[2:0] > current_floor) && floor_req[i])
                            next_target_floor = i[2:0];
                    if (next_target_floor != current_floor) begin
                        next_direction = 1'b1;
                        next_state     = MOVING_UP;
                    end else begin
                        for (i = 0; i < 5; i = i + 1)
                            if ((i[2:0] < current_floor) && floor_req[i])
                                next_target_floor = i[2:0];
                        if (next_target_floor != current_floor) begin
                            next_direction = 1'b0;
                            next_state     = MOVING_DOWN;
                        end else
                            next_state = IDLE;
                    end
                end else
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    // FSM — Sequential (state register, floor counter, timers)
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            current_floor  <= 3'd0;
            target_floor   <= 3'd0;
            direction      <= 1'b1;
            post_emergency <= 1'b0;
            door_timer     <= 24'd0;
        end else begin
            // Post-emergency flag management
            if (state != EMERG_STOP && next_state == EMERG_STOP)
                post_emergency <= 1'b1;
            if ((state == RETURN_TO_F1 || state == DOOR_CLOSING) && current_floor == 3'd1)
                post_emergency <= 1'b0;

            // Update state registers
            state        <= next_state;
            target_floor <= next_target_floor;
            direction    <= next_direction;

            // Door timer: increment while staying in same door state, else reset
            if ((state == DOOR_OPENING && next_state == DOOR_OPENING) ||
                (state == DOOR_CLOSING && next_state == DOOR_CLOSING))
                door_timer <= door_timer + 24'd1;
            else
                door_timer <= 24'd0;

            // Floor movement (applied on the cycle AFTER entering MOVING state)
            case (state)
                MOVING_UP:   if (current_floor < 3'd4) current_floor <= current_floor + 3'd1;
                MOVING_DOWN: if (current_floor > 3'd0) current_floor <= current_floor - 3'd1;
                default: ;  // No movement
            endcase
        end
    end

endmodule
