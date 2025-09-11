// 디바운스 모듈 - 스위치 입력 안정화를 위한 모듈
module debounce(
  input wire clk,
  input wire reset,          // 활성화 낮음(버튼)
  input wire sw,
  output reg db
);

  // 상수 선언 - 2^19 * 20ns = 10ms tick
  localparam N = 19;
  
  // 내부 신호 선언
  reg [N-1:0] q_reg;
  wire [N-1:0] q_next;
  wire m_tick;
  
  // FSM 상태 정의
  localparam 
    ZERO = 3'd0,
    WAIT1_1 = 3'd1,
    WAIT1_2 = 3'd2,
    WAIT1_3 = 3'd3,
    ONE = 3'd4,
    WAIT0_1 = 3'd5,
    WAIT0_2 = 3'd6,
    WAIT0_3 = 3'd7;
    
  reg [2:0] state_reg, state_next;
  
  // 10ms 틱 생성을 위한 카운터
  always @(posedge clk) begin
    q_reg <= q_next;
  end
  
  // 다음 상태 로직
  assign q_next = q_reg + 1;
  
  // 출력 틱
  assign m_tick = (q_reg == 0) ? 1'b1 : 1'b0;
  
  // 디바운스 FSM - 상태 레지스터
  always @(posedge clk) begin
    if (!reset)              // 리셋 활성화(낮음)
      state_reg <= ZERO;
    else
      state_reg <= state_next;
  end
  
  // 다음 상태/출력 로직
  always @(*) begin
    // 기본값 설정
    state_next = state_reg;
    db = 1'b0;
    
    case (state_reg)
      ZERO: begin
        if (sw)
          state_next = WAIT1_1;
      end
      
      WAIT1_1: begin
        if (!sw)
          state_next = ZERO;
        else if (m_tick)
          state_next = WAIT1_2;
      end
      
      WAIT1_2: begin
        if (!sw)
          state_next = ZERO;
        else if (m_tick)
          state_next = WAIT1_3;
      end
      
      WAIT1_3: begin
        if (!sw)
          state_next = ZERO;
        else if (m_tick)
          state_next = ONE;
      end
      
      ONE: begin
        db = 1'b1;
        if (!sw)
          state_next = WAIT0_1;
      end
      
      WAIT0_1: begin
        db = 1'b1;
        if (sw)
          state_next = ONE;
        else if (m_tick)
          state_next = WAIT0_2;
      end
      
      WAIT0_2: begin
        db = 1'b1;
        if (sw)
          state_next = ONE;
        else if (m_tick)
          state_next = WAIT0_3;
      end
      
      WAIT0_3: begin
        db = 1'b1;
        if (sw)
          state_next = ONE;
        else if (m_tick)
          state_next = ZERO;
      end
    endcase
  end

endmodule