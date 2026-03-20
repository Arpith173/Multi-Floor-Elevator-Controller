//============================================================================
// Module: button_debouncer
// Description: Two-stage synchronizer with rising-edge detector for
//              debouncing mechanical push buttons.
//              Produces a single-cycle pulse on each rising edge of the
//              synchronized input.
//============================================================================

module button_debouncer #(
    parameter NUM_BUTTONS = 5
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire [NUM_BUTTONS-1:0]  btn_in,     // Raw button inputs
    output reg  [NUM_BUTTONS-1:0]  btn_pulse   // Single-cycle rising-edge pulses
);

    reg [NUM_BUTTONS-1:0] sync_0;   // First synchronizer stage
    reg [NUM_BUTTONS-1:0] sync_1;   // Second synchronizer stage
    reg [NUM_BUTTONS-1:0] prev;     // Previous synchronized value

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync_0    <= {NUM_BUTTONS{1'b0}};
            sync_1    <= {NUM_BUTTONS{1'b0}};
            prev      <= {NUM_BUTTONS{1'b0}};
            btn_pulse <= {NUM_BUTTONS{1'b0}};
        end else begin
            sync_0    <= btn_in;
            sync_1    <= sync_0;
            btn_pulse <= (~prev) & sync_1;   // Rising edge detection
            prev      <= sync_1;
        end
    end

endmodule
