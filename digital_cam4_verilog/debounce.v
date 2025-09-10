// 스위치 디바운싱 모듈
// 기계식 스위치 입력의 채터링(chattering) 현상을 제거합니다.
// Pong P. Chu의 책에서 발췌 및 수정되었습니다.

module debounce (
    input clk,     // 클럭
    input reset,   // 리셋 (액티브 하이)
    input sw,      // 디바운싱할 스위치 입력
    output db     // 디바운싱된 출력
);

    // 10ms 틱 생성을 위한 카운터 설정
    // 50MHz 클럭(20ns) 기준: 2^19 * 20ns ≈ 10.5ms
    parameter N = 19;
    reg [N-1:0] q_reg;
    wire m_tick;

    // 10ms 틱 생성 카운터
    always @(posedge clk) begin
        q_reg <= q_reg + 1;
    end

    // 카운터가 0이 될 때마다 1클럭 동안 m_tick 신호를 생성
    // VHDL 코드의 동작을 그대로 따름
    assign m_tick = (q_reg == {N{1'b0}});

    // 디바운싱 FSM 상태 정의
    parameter ZERO    = 3'd0,
              WAIT1_1 = 3'd1,
              WAIT1_2 = 3'd2,
              WAIT1_3 = 3'd3,
              ONE     = 3'd4,
              WAIT0_1 = 3'd5,
              WAIT0_2 = 3'd6,
              WAIT0_3 = 3'd7;

    reg [2:0] state_reg, state_next;
    reg db_reg;

    // FSM 상태 레지스터 (순차 회로)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_reg <= ZERO;
        end else begin
            state_reg <= state_next;
        end
    end
    
    // FSM 다음 상태 및 출력 로직 (조합 회로)
    always @(*) begin
        // 기본값 설정
        state_next = state_reg;
        db_reg = 1'b0; // 기본 출력은 0

        case (state_reg)
            ZERO: begin
                if (sw) state_next = WAIT1_1;
            end
            WAIT1_1: begin
                if (!sw) state_next = ZERO;
                else if (m_tick) state_next = WAIT1_2;
            end
            WAIT1_2: begin
                if (!sw) state_next = ZERO;
                else if (m_tick) state_next = WAIT1_3;
            end
            WAIT1_3: begin
                if (!sw) state_next = ZERO;
                else if (m_tick) state_next = ONE;
            end
            ONE: begin
                db_reg = 1'b1;
                if (!sw) state_next = WAIT0_1;
            end
            WAIT0_1: begin
                db_reg = 1'b1;
                if (sw) state_next = ONE;
                else if (m_tick) state_next = WAIT0_2;
            end
            WAIT0_2: begin
                db_reg = 1'b1;
                if (sw) state_next = ONE;
                else if (m_tick) state_next = WAIT0_3;
            end
            WAIT0_3: begin
                db_reg = 1'b1;
                if (sw) state_next = ONE;
                else if (m_tick) state_next = ZERO;
            end
            default: state_next = ZERO;
        endcase
    end

    assign db = db_reg;

endmodule
