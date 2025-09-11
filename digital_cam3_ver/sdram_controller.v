module sdram_controller(
  input wire clk_i,            // 클럭 100MHz
  input wire dram_clk_i,       // 클럭 100MHz -3ns 위상조정
  input wire rst_i,            // 리셋
  input wire dll_locked,       // PLL 잠금 상태
  
  // SDRAM 신호
  output reg [12:0] dram_addr,  // 주소 버스
  output reg [1:0] dram_bank,   // 뱅크 선택
  output reg dram_cas_n,        // 컬럼 주소 스트로브
  output wire dram_cke,         // 클럭 활성화
  output wire dram_clk,         // SDRAM 클럭
  output wire dram_cs_n,        // 칩 선택
  inout wire [15:0] dram_dq,    // 데이터 버스
  output wire dram_ldqm,        // 하위 데이터 마스크
  output wire dram_udqm,        // 상위 데이터 마스크
  output reg dram_ras_n,        // 행 주소 스트로브
  output reg dram_we_n,         // 쓰기 활성화
  
  // Wishbone 버스
  input wire [24:0] addr_i,     // 주소 입력
  input wire [31:0] dat_i,      // 데이터 입력
  output wire [31:0] dat_o,     // 데이터 출력
  input wire we_i,              // 쓰기 활성화 입력
  output reg ack_o,             // 응답 신호
  input wire stb_i,             // 스트로브 입력
  input wire cyc_i              // 사이클 입력
);

  // 행 너비 13
  // 컬럼 너비 10
  // 뱅크 너비 2
  // 사용자 주소는 {bank,row,column} 형식으로 지정됨

  // 모드 레지스터 설정
  // BL=2 (A2 A1 A0 = "001"), 순차 타입 (A3 = '0'), CAS=3 (A6 A5 A4 = "011")
  localparam [12:0] MODE_REGISTER = 13'b0000000110001;
    
  // 초기화 상태
  localparam [2:0] INIT_IDLE          = 3'b000;
  localparam [2:0] INIT_WAIT_200us    = 3'b001;
  localparam [2:0] INIT_INIT_PRE      = 3'b010;
  localparam [2:0] INIT_WAIT_PRE      = 3'b011;
  localparam [2:0] INIT_MODE_REG      = 3'b100;
  localparam [2:0] INIT_WAIT_MODE_REG = 3'b101;
  localparam [2:0] INIT_DONE_ST       = 3'b110;

  // 작동 상태
  localparam [3:0] IDLE_ST         = 4'b0000;
  localparam [3:0] REFRESH_ST      = 4'b0001;
  localparam [3:0] REFRESH_WAIT_ST = 4'b0010;
  localparam [3:0] ACT_ST          = 4'b0011;
  localparam [3:0] WAIT_ACT_ST     = 4'b0100;
  localparam [3:0] WRITE0_ST       = 4'b0101;
  localparam [3:0] WRITE1_ST       = 4'b0110;
  localparam [3:0] WRITE_PRE_ST    = 4'b0111;
  localparam [3:0] READ0_ST        = 4'b1000;
  localparam [3:0] READ1_ST        = 4'b1001;
  localparam [3:0] READ2_ST        = 4'b1010;
  localparam [3:0] READ3_ST        = 4'b1011;
  localparam [3:0] READ4_ST        = 4'b1100;
  localparam [3:0] READ_PRE_ST     = 4'b1101;
  localparam [3:0] PRE_ST          = 4'b1110;
  localparam [3:0] WAIT_PRE_ST     = 4'b1111;

  // 타이밍 파라미터 (100MHz 기준)
  // 리프레시 후 대기 시간 70ns -> 10 사이클
  localparam [3:0] TRC_CNTR_VALUE = 4'b1010;
  // 리프레시 간격 64ms/8192 = 7.8us -> 780 사이클
  localparam [24:0] RFSH_INT_CNTR_VALUE = 25'd780;
  // RAS to CAS 지연 20ns -> 2 사이클
  localparam [2:0] TRCD_CNTR_VALUE = 3'b010;
  // 초기화 지연 200us -> 20000 사이클
  localparam [15:0] WAIT_200us_CNTR_VALUE = 16'd20000;

  // 내부 신호
  reg [24:0] address_r;
  reg [12:0] dram_addr_r;
  reg [1:0] dram_bank_r;
  reg [15:0] dram_dq_r;
  reg dram_cas_n_r;
  reg dram_ras_n_r;
  reg dram_we_n_r;
  
  reg [31:0] dat_o_r = 32'b0;
  reg ack_o_r = 1'b0;
  reg [31:0] dat_i_r;
  reg we_i_r = 1'b0;
  reg stb_i_r;
  reg oe_r = 1'b0;

  reg [3:0] current_state = IDLE_ST;
  reg [3:0] next_state = IDLE_ST;
  reg [2:0] current_init_state = INIT_IDLE;
  reg [2:0] next_init_state = INIT_IDLE;
    
  reg init_done = 1'b0;
  reg [3:0] init_pre_cntr = 4'b0;
  reg [3:0] trc_cntr = 4'b0;
  reg [24:0] rfsh_int_cntr = 25'b0;
  reg [2:0] trcd_cntr = 3'b0;
  reg [15:0] wait_200us_cntr = 16'b0;
  reg do_refresh;

  // 출력 할당
  assign dram_dq = oe_r ? dram_dq_r : 16'bz;
  assign dat_o = dat_o_r;
  assign dram_cke = 1'b1;
  assign dram_cs_n = ~dll_locked;
  assign dram_clk = dram_clk_i;
  assign dram_ldqm = 1'b0;
  assign dram_udqm = 1'b0;

  // 버스 상태 갱신
  always @(posedge clk_i) begin
    if (stb_i_r && current_state == ACT_ST) begin
      stb_i_r <= 1'b0;
    end
    else if (stb_i && cyc_i) begin
      address_r <= addr_i;
      dat_i_r <= dat_i;
      we_i_r <= we_i;
      stb_i_r <= stb_i;
    end
  end

  // 초기화 지연 카운터
  always @(posedge clk_i) begin
    if (rst_i) begin
      wait_200us_cntr <= 16'b0;
    end
    else if (current_init_state == INIT_IDLE) begin
      wait_200us_cntr <= WAIT_200us_CNTR_VALUE;
    end
    else begin
      wait_200us_cntr <= wait_200us_cntr - 1;
    end
  end

  // 리프레시 간격 카운터
  always @(posedge clk_i) begin
    if (rst_i) begin
      rfsh_int_cntr <= 25'b0;
    end
    else if (current_state == REFRESH_WAIT_ST) begin
      do_refresh <= 1'b0;
      rfsh_int_cntr <= RFSH_INT_CNTR_VALUE;
    end
    else if (rfsh_int_cntr == 25'b0) begin
      do_refresh <= 1'b1;
    end
    else begin
      rfsh_int_cntr <= rfsh_int_cntr - 1;
    end
  end

  // TRC 카운터
  always @(posedge clk_i) begin
    if (rst_i) begin
      trc_cntr <= 4'b0;
    end
    else if (current_state == PRE_ST || current_state == REFRESH_ST) begin
      trc_cntr <= TRC_CNTR_VALUE;
    end
    else begin
      trc_cntr <= trc_cntr - 1;
    end
  end

  // TRCD 카운터
  always @(posedge clk_i) begin
    if (rst_i) begin
      trcd_cntr <= 3'b0;
    end
    else if (current_state == ACT_ST || current_init_state == INIT_INIT_PRE 
      || current_init_state == INIT_MODE_REG) begin
      trcd_cntr <= TRCD_CNTR_VALUE;
    end
    else begin
      trcd_cntr <= trcd_cntr - 1;
    end
  end

  // 초기화 프리차지 카운터
  always @(posedge clk_i) begin
    if (rst_i) begin
      init_pre_cntr <= 4'b0;
    end
    else if (current_init_state == INIT_INIT_PRE) begin
      init_pre_cntr <= init_pre_cntr + 1;
    end
  end

  // 초기화 완료 신호
  always @(posedge clk_i) begin
    if (current_init_state == INIT_DONE_ST) begin
      init_done <= 1'b1;
    end
  end

  // 상태 변경
  always @(posedge clk_i) begin
    if (rst_i) begin
      current_init_state <= INIT_IDLE;
    end
    else begin
      current_init_state <= next_init_state;
    end
  end

  always @(posedge clk_i) begin
    if (rst_i) begin
      current_state <= IDLE_ST;
    end
    else begin
      current_state <= next_state;
    end
  end

  // 초기화 FSM
  always @(*) begin
    case (current_init_state)
      INIT_IDLE: begin
        if (init_done == 1'b0) begin
          next_init_state = INIT_WAIT_200us;
        end
        else begin
          next_init_state = INIT_IDLE;
        end
      end
      
      INIT_WAIT_200us: begin
        if (wait_200us_cntr == 16'b0) begin
          next_init_state = INIT_INIT_PRE;
        end
        else begin
          next_init_state = INIT_WAIT_200us;
        end
      end
      
      INIT_INIT_PRE: begin
        next_init_state = INIT_WAIT_PRE;
      end

      INIT_WAIT_PRE: begin
        if (trcd_cntr == 3'b0) begin
          if (init_pre_cntr == 4'b1000) begin
            next_init_state = INIT_MODE_REG;
          end
          else begin
            next_init_state = INIT_INIT_PRE;
          end
        end
        else begin
          next_init_state = INIT_WAIT_PRE;
        end
      end

      INIT_MODE_REG: begin
        next_init_state = INIT_WAIT_MODE_REG;
      end
      
      INIT_WAIT_MODE_REG: begin
        if (trcd_cntr == 3'b0) begin
          next_init_state = INIT_DONE_ST;
        end
        else begin
          next_init_state = INIT_WAIT_MODE_REG;
        end
      end
    
      INIT_DONE_ST: begin
        next_init_state = INIT_IDLE;
      end

      default: begin
        next_init_state = INIT_IDLE;
      end
    endcase
  end

  // 메인 컨트롤러 FSM
  always @(*) begin
    case (current_state)
      IDLE_ST: begin
        if (init_done == 1'b0) begin
          next_state = IDLE_ST;
        end
        else if (do_refresh == 1'b1) begin
          next_state = REFRESH_ST;
        end
        else if (stb_i_r == 1'b1) begin
          next_state = ACT_ST;
        end
        else begin
          next_state = IDLE_ST;
        end
      end
      
      REFRESH_ST: begin
        next_state = REFRESH_WAIT_ST;
      end

      REFRESH_WAIT_ST: begin
        if (trc_cntr == 4'b0) begin
          next_state = IDLE_ST;
        end
        else begin
          next_state = REFRESH_WAIT_ST;
        end
      end
      
      ACT_ST: begin
        next_state = WAIT_ACT_ST;
      end
      
      WAIT_ACT_ST: begin
        if (trcd_cntr == 3'b0) begin
          if (we_i_r == 1'b1) begin
            next_state = WRITE0_ST;
          end
          else begin
            next_state = READ0_ST;
          end
        end
        else begin
          next_state = WAIT_ACT_ST;
        end
      end
      
      WRITE0_ST: begin
        next_state = WRITE1_ST;
      end

      WRITE1_ST: begin
        next_state = WRITE_PRE_ST;
      end
      
      WRITE_PRE_ST: begin
        next_state = PRE_ST;
      end
      
      READ0_ST: begin
        next_state = READ1_ST;
      end

      READ1_ST: begin
        next_state = READ2_ST;
      end
      
      READ2_ST: begin
        next_state = READ3_ST;
      end

      READ3_ST: begin
        next_state = READ4_ST;
      end

      READ4_ST: begin
        next_state = READ_PRE_ST;
      end

      READ_PRE_ST: begin
        next_state = PRE_ST;
      end
      
      PRE_ST: begin
        next_state = WAIT_PRE_ST;
      end
      
      WAIT_PRE_ST: begin
        if (trc_cntr == 4'b0) begin
          next_state = IDLE_ST;
        end
        else begin
          next_state = WAIT_PRE_ST;
        end
      end

      default: begin
        next_state = IDLE_ST;
      end
    endcase
  end

  // ack_o 신호 생성
  always @(posedge clk_i) begin
    if (current_state == READ_PRE_ST || current_state == WRITE_PRE_ST) begin
      ack_o_r <= 1'b1;
    end
    else if (current_state == WAIT_PRE_ST) begin
      ack_o_r <= 1'b0;
    end
  end
  
  // 데이터 처리
  always @(posedge clk_i) begin
    if (rst_i) begin
      dat_o_r <= 32'b0;
      dram_dq_r <= 16'b0;
      oe_r <= 1'b0;
    end
    else if (current_state == WRITE0_ST) begin
      dram_dq_r <= dat_i_r[31:16];
      oe_r <= 1'b1;
    end
    else if (current_state == WRITE1_ST) begin
      dram_dq_r <= dat_i_r[15:0];
      oe_r <= 1'b1;
    end
    else if (current_state == READ4_ST) begin
      dat_o_r[31:16] <= dram_dq;
      dram_dq_r <= 16'bz;
      oe_r <= 1'b0;
    end
    else if (current_state == READ_PRE_ST) begin
      dat_o_r[15:0] <= dram_dq;
      dram_dq_r <= 16'bz;
      oe_r <= 1'b0;
    end
    else begin
      dram_dq_r <= 16'bz;
      oe_r <= 1'b0;
    end
  end

  // 주소 제어
  always @(posedge clk_i) begin
    if (current_init_state == INIT_MODE_REG) begin
      dram_addr_r <= MODE_REGISTER;
    end
    else if (current_init_state == INIT_INIT_PRE) begin
      dram_addr_r <= 13'b0010000000000;  // A[10] = '1' 모든 뱅크 프리차지
    end
    else if (current_state == ACT_ST) begin
      dram_addr_r <= address_r[22:10];
      dram_bank_r <= address_r[24:23];
    end
    else if (current_state == WRITE0_ST || current_state == READ0_ST) begin
      dram_addr_r <= {3'b001, address_r[9:0]};  // A10=1 자동 프리차지 표시
      dram_bank_r <= address_r[24:23];
    end
    else begin
      dram_addr_r <= 13'b0;
      dram_bank_r <= 2'b00;
    end
  end

  // 명령어 제어
  always @(posedge clk_i) begin
    if (current_init_state == INIT_INIT_PRE 
      || current_init_state == INIT_MODE_REG 
      || current_state == REFRESH_ST 
      || current_state == ACT_ST) begin
      dram_ras_n_r <= 1'b0;
    end
    else begin
      dram_ras_n_r <= 1'b1;
    end
    
    if (current_state == READ0_ST 
      || current_state == WRITE0_ST 
      || current_state == REFRESH_ST 
      || current_init_state == INIT_MODE_REG) begin
      dram_cas_n_r <= 1'b0;
    end
    else begin
      dram_cas_n_r <= 1'b1;
    end
     
    if (current_init_state == INIT_INIT_PRE 
      || current_state == WRITE0_ST 
      || current_init_state == INIT_MODE_REG) begin
      dram_we_n_r <= 1'b0;
    end
    else begin
      dram_we_n_r <= 1'b1;
    end
  end

  // 최종 출력 할당
  always @(*) begin
    dram_addr = dram_addr_r;
    dram_bank = dram_bank_r;
    dram_cas_n = dram_cas_n_r;
    dram_ras_n = dram_ras_n_r;
    dram_we_n = dram_we_n_r;
    ack_o = ack_o_r;
  end
  
endmodule
