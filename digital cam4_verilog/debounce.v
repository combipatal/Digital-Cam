// VHDL 소스 파일: debounce.vhd
// 스위치 입력의 채터링을 제거하기 위한 디바운싱 회로

module debounce (
    input wire clk,
    input wire reset,
    input wire sw,
    output reg db
);

    parameter N = 19; // 2^N * clk_period = 10ms tick (2^19 * 20ns for 50MHz clk)

    reg [N-1:0] q_reg;
    wire m_tick;

    // 10ms 틱 생성용 카운터
    always @(posedge clk) begin
        q_reg <= q_reg + 1;
    end
    assign m_tick = (q_reg == 0);

    // FSM 상태 정의
    localparam [2:0] zero    = 3'b000,
                     wait1_1 = 3'b001,
                     wait1_2 = 3'b010,
                     wait1_3 = 3'b011,
                     one     = 3'b100,
                     wait0_1 = 3'b101,
                     wait0_2 = 3'b110,
                     wait0_3 = 3'b111;

    reg [2:0] state_reg, state_next;

    // FSM 상태 레지스터
    always @(posedge clk or posedge reset) begin
        if (reset)
            state_reg <= zero;
        else
            state_reg <= state_next;
    end

    // FSM 다음 상태 및 출력 로직
    always @(*) begin
        state_next = state_reg; // 기본값: 현재 상태 유지
        db = 1'b0;              // 기본 출력: 0

        case (state_reg)
            zero: begin
                if (sw) state_next = wait1_1;
            end
            wait1_1: begin
                if (~sw) state_next = zero;
                else if (m_tick) state_next = wait1_2;
            end
            wait1_2: begin
                if (~sw) state_next = zero;
                else if (m_tick) state_next = wait1_3;
            end
            wait1_3: begin
                if (~sw) state_next = zero;
                else if (m_tick) state_next = one;
            end
            one: begin
                db = 1'b1;
                if (~sw) state_next = wait0_1;
            end
            wait0_1: begin
                db = 1'b1;
                if (sw) state_next = one;
                else if (m_tick) state_next = wait0_2;
            end
            wait0_2: begin
                db = 1'b1;
                if (sw) state_next = one;
                else if (m_tick) state_next = wait0_3;
            end
            wait0_3: begin
                db = 1'b1;
                if (sw) state_next = one;
                else if (m_tick) state_next = zero;
            end
            default: state_next = zero;
        endcase
    end

endmodule
