// Simple debouncing technique for slide switches
// Adapted from Pong P. Chu's book

module debounce(
    input clk,
    input reset,
    input sw,
    output reg db
);

    parameter N = 19; // 2^N * 20ns = 10ms tick

    reg [N-1:0] q_reg, q_next;
    reg m_tick;

    // State machine states
    localparam [2:0]
        zero = 3'b000,
        wait1_1 = 3'b001,
        wait1_2 = 3'b010,
        wait1_3 = 3'b011,
        one = 3'b100,
        wait0_1 = 3'b101,
        wait0_2 = 3'b110,
        wait0_3 = 3'b111;

    reg [2:0] state_reg, state_next;

    // Counter for 10ms tick generation
    always @(posedge clk) begin
        q_reg <= q_next;
    end

    // Next-state logic for counter
    always @* begin
        q_next = q_reg + 1;
    end

    // Output tick
    always @* begin
        m_tick = (q_reg == 0) ? 1'b1 : 1'b0;
    end

    // State register
    always @(posedge clk, posedge reset) begin
        if (reset)
            state_reg <= zero;
        else
            state_reg <= state_next;
    end

    // Next-state/output logic
    always @* begin
        state_next = state_reg; // default: back to same state
        db = 1'b0; // default 0

        case (state_reg)
            zero: begin
                if (sw == 1'b1)
                    state_next = wait1_1;
            end

            wait1_1: begin
                if (sw == 1'b0)
                    state_next = zero;
                else if (m_tick == 1'b1)
                    state_next = wait1_2;
            end

            wait1_2: begin
                if (sw == 1'b0)
                    state_next = zero;
                else if (m_tick == 1'b1)
                    state_next = wait1_3;
            end

            wait1_3: begin
                if (sw == 1'b0)
                    state_next = zero;
                else if (m_tick == 1'b1)
                    state_next = one;
            end

            one: begin
                db = 1'b1;
                if (sw == 1'b0)
                    state_next = wait0_1;
            end

            wait0_1: begin
                db = 1'b1;
                if (sw == 1'b1)
                    state_next = one;
                else if (m_tick == 1'b1)
                    state_next = wait0_2;
            end

            wait0_2: begin
                db = 1'b1;
                if (sw == 1'b1)
                    state_next = one;
                else if (m_tick == 1'b1)
                    state_next = wait0_3;
            end

            wait0_3: begin
                db = 1'b1;
                if (sw == 1'b1)
                    state_next = one;
                else if (m_tick == 1'b1)
                    state_next = zero;
            end

            default: begin
                state_next = zero;
                db = 1'b0;
            end
        endcase
    end

endmodule
