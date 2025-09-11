module sdram_rw(
  // SDRAM 컨트롤러 연결
  input wire clk_i,               // 25MHz
  input wire rst_i,               // 리셋
  output reg [24:0] addr_i,       // 주소 버스
  output reg [31:0] dat_i,        // 데이터 출력
  input wire [31:0] dat_o,        // 데이터 입력
  output reg we_i,                // 쓰기 활성화
  input wire ack_o,               // 응답 신호
  output reg stb_i,               // 스트로브
  output reg cyc_i,               // 사이클
  
  // 프레임 버퍼 2 연결 (SDRAM에서 읽은 이미지 데이터 전달)
  output reg [16:0] addr_buf2,    // 주소
  output reg [11:0] dout_buf2,    // 데이터 출력
  output reg we_buf2,             // 쓰기 활성화
  
  // 프레임 버퍼 1 연결 (스냅샷 저장)
  output reg [16:0] addr_buf1,    // 주소
  input wire [11:0] din_buf1,     // 데이터 입력
  
  // 제어 신호
  input wire take_snapshot,       // SDRAM에 저장
  input wire display_snapshot,    // SDRAM에서 표시
  output reg led_done             // 완료 표시
);

  // 상태 정의
  localparam START_WRITE_ST     = 4'b0000;
  localparam WRITE_ST           = 4'b0001;
  localparam WAIT_WRITE_ACK_ST  = 4'b0010;
  localparam READ_ST            = 4'b0011;
  localparam WAIT_READ_ACK_ST   = 4'b0100;
  localparam WRITE_WAIT_ST      = 4'b0101;
  localparam START_READ_ST      = 4'b0110;
  localparam READ_WAIT_ST       = 4'b0111;
  localparam DONE_ST            = 4'b1000;
  localparam IDLE_ST            = 4'b1001;

  // 상수
  localparam [16:0] NUM_PIXELS = 17'd76799; // 320x240 = 76800 워드

  // 내부 신호
  reg led_done_r = 1'b0;

  // 버퍼 1 관련 신호 (SDRAM 저장용)
  reg [16:0] addr_buf1_r = 17'b0;
  reg [11:0] din_buf1_r;
  
  // 버퍼 2 관련 신호 (디스플레이용)
  reg [16:0] addr_buf2_r = 17'b0;
  reg [11:0] dout_buf2_r = 12'b0;
  reg we_buf2_r = 1'b0;

  // 픽셀 카운터 및 상태
  reg [16:0] rw_cntr = 17'b0;
  reg [3:0] state = IDLE_ST;

  // SDRAM 컨트롤러 연결 신호
  reg [24:0] addr_i_r = 25'b0;
  reg [31:0] dat_i_r;
  reg [31:0] dat_o_r;
  reg we_i_r = 1'b0;
  reg stb_i_r = 1'b0;
  reg cyc_i_r = 1'b0;

  // 신호 할당
  always @(*) begin
    dat_o_r = dat_o;
    addr_i = addr_i_r;
    dat_i = dat_i_r;
    stb_i = stb_i_r;
    cyc_i = cyc_i_r;
    we_i = we_i_r;
    
    addr_buf1 = addr_buf1_r;
    din_buf1_r = din_buf1;
    
    addr_buf2 = addr_buf2_r;
    dout_buf2 = dout_buf2_r;
    we_buf2 = we_buf2_r;
    
    led_done = led_done_r;
  end

  // 메인 상태 머신
  always @(posedge clk_i) begin
    if (rst_i) begin
      state <= IDLE_ST;
      led_done_r <= 1'b0;
      we_buf2_r <= 1'b0;
    end
    else if (take_snapshot && state == IDLE_ST) begin
      state <= START_WRITE_ST;
      led_done_r <= 1'b0;
      we_buf2_r <= 1'b0;
      addr_buf1_r <= 17'b0;
    end
    else if (display_snapshot && state == IDLE_ST) begin
      state <= START_READ_ST;
      led_done_r <= 1'b0;
      we_buf2_r <= 1'b1;
      addr_buf2_r <= 17'b0;
    end
    else begin
      case (state)
        // 쓰기 상태들 (스냅샷 저장)
        START_WRITE_ST: begin
          state <= WRITE_ST;
          addr_i_r <= 25'b0;
          rw_cntr <= 17'b0;
          we_i_r <= 1'b1;
          addr_buf1_r <= 17'b0;
        end
        
        WRITE_ST: begin
          state <= WAIT_WRITE_ACK_ST;
          stb_i_r <= 1'b1;
          cyc_i_r <= 1'b1;
          we_i_r <= 1'b1;
          dat_i_r <= {20'b0, din_buf1_r};
          addr_buf1_r <= addr_buf1_r + 1;
        end
        
        WAIT_WRITE_ACK_ST: begin
          if (ack_o) begin
            state <= WRITE_WAIT_ST;
            stb_i_r <= 1'b0;
            cyc_i_r <= 1'b0;
          end
        end
        
        WRITE_WAIT_ST: begin
          if (rw_cntr < NUM_PIXELS) begin
            state <= WRITE_ST;
            rw_cntr <= rw_cntr + 1;
            addr_i_r <= addr_i_r + 2;
          end
          else begin
            state <= DONE_ST;
          end
        end
        
        // 읽기 상태들 (스냅샷 표시)
        START_READ_ST: begin
          addr_i_r <= 25'b0;
          rw_cntr <= 17'b0;
          we_i_r <= 1'b0;
          addr_buf2_r <= 17'b0;
          dout_buf2_r <= 12'b110000000011; // 노란색
          we_buf2_r <= 1'b1;
          state <= READ_ST;
        end
        
        READ_ST: begin
          stb_i_r <= 1'b1;
          cyc_i_r <= 1'b1;
          we_i_r <= 1'b0;
          state <= WAIT_READ_ACK_ST;
        end
        
        WAIT_READ_ACK_ST: begin
          if (ack_o) begin
            stb_i_r <= 1'b0;
            cyc_i_r <= 1'b0;
            dout_buf2_r <= dat_o_r[11:0];
            state <= READ_WAIT_ST;
          end
        end

        READ_WAIT_ST: begin
          if (rw_cntr < NUM_PIXELS) begin
            rw_cntr <= rw_cntr + 1;
            addr_i_r <= addr_i_r + 2;
            addr_buf2_r <= addr_buf2_r + 1;
            state <= READ_ST;
          end
          else begin
            state <= DONE_ST;
          end
        end
        
        DONE_ST: begin
          state <= DONE_ST;  // 한 프레임만 한 번 처리
          led_done_r <= 1'b1;  // 완료 알림
        end
        
        default: begin // IDLE_ST
          state <= IDLE_ST;
          led_done_r <= 1'b0;
        end
      endcase
    end
  end

endmodule
