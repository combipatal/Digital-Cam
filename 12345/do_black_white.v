module do_black_white(
  // 제어
  input wire rst_i,
  input wire clk_i,  // 25 MHz
  input wire enable_filter,
  output reg led_done,
  // 프레임 버퍼 2에서 이미지 데이터를 읽기 위한 연결
  output reg [16:0] rdaddr_buf2,
  input wire [11:0] din_buf2,
  // 처리 후 버퍼 2에 쓰기 위한 연결
  output reg [16:0] wraddr_buf2,
  output wire [11:0] dout_buf2,
  output reg we_buf2
);

  // 상태 정의
  localparam START_BLACKWHITE_ST  = 3'b000;
  localparam GET_PIXEL_DATA_ST    = 3'b001;
  localparam WAIT_ACK_DIVISION_ST = 3'b010;
  localparam SEND_PIXEL_DATA_ST   = 3'b011;
  localparam DONE_ST              = 3'b100;
  localparam IDLE_ST              = 3'b101;

  // 상수 정의
  localparam [7:0] CONSTANT_THREE = 8'b00000011;
  localparam [16:0] NUM_PIXELS = 17'd76799;
  
  // 신호 선언
  reg led_done_r = 1'b0;
  reg [16:0] rdaddr_buf2_r = 17'b0;
  reg [11:0] din_buf2_r;
  reg [16:0] wraddr_buf2_r = 17'b0;
  reg [11:0] dout_buf2_r = 12'b0;
  reg we_buf2_r = 1'b0;
  
  reg [16:0] rw_cntr = 17'b0;
  reg [2:0] state = IDLE_ST;

  // 컬러 채널 분리
  reg [7:0] red, green, blue;
  wire [7:0] red_grey, green_grey, blue_grey;
  reg [7:0] r_plus_g_plus_b;
  wire [7:0] remainder_not_used;
  
  // 이진 나눗셈기 인스턴스
  binary_divider_ver1 #(.size(8)) Inst_binary_divider (
    .A(r_plus_g_plus_b),
    .B(CONSTANT_THREE),
    .Q(red_grey),
    .R(remainder_not_used)
  );
  
  // 출력 할당
  assign led_done = led_done_r;
  assign dout_buf2 = dout_buf2_r;

  // 픽셀 데이터 처리
  always @(*) begin
    red = {4'b0000, din_buf2_r[11:8]};
    green = {4'b0000, din_buf2_r[7:4]};
    blue = {4'b0000, din_buf2_r[3:0]};
    r_plus_g_plus_b = red + green + blue;
    
    // 결과 생성
    dout_buf2_r = {red_grey[3:0], red_grey[3:0], red_grey[3:0]};
  end
  
  // 메인 FSM 프로세스
  always @(posedge clk_i) begin
    if (rst_i) begin
      state <= IDLE_ST;
      led_done_r <= 1'b0;
      we_buf2_r <= 1'b0;
    end
    else if (enable_filter == 1'b1 && state == IDLE_ST) begin
      state <= START_BLACKWHITE_ST;
      rw_cntr <= 17'b0;
      we_buf2_r <= 1'b1;
      led_done_r <= 1'b0;
      rdaddr_buf2_r <= 17'b0;
      wraddr_buf2_r <= 17'b0;
    end
    else begin
      case (state)
        START_BLACKWHITE_ST: begin
          state <= GET_PIXEL_DATA_ST;
          rw_cntr <= 17'b0;
          we_buf2_r <= 1'b1;
          rdaddr_buf2_r <= 17'b0;
          wraddr_buf2_r <= 17'b0;
        end
        
        GET_PIXEL_DATA_ST: begin
          state <= SEND_PIXEL_DATA_ST;
          rdaddr_buf2_r <= rdaddr_buf2_r + 1;
          wraddr_buf2_r <= wraddr_buf2_r + 1;
        end
        
        WAIT_ACK_DIVISION_ST: begin
          state <= SEND_PIXEL_DATA_ST;
          wraddr_buf2_r <= wraddr_buf2_r + 1;
        end
        
        SEND_PIXEL_DATA_ST: begin
          if (rw_cntr < NUM_PIXELS) begin
            state <= GET_PIXEL_DATA_ST;
            rw_cntr <= rw_cntr + 1;
          end
          else begin
            state <= DONE_ST;
          end
        end
        
        DONE_ST: begin
          state <= DONE_ST;  // 모든 픽셀을 한 번만 처리하도록
          led_done_r <= 1'b1;  // 완료 알림
          we_buf2_r <= 1'b0;
        end
        
        default: begin  // IDLE_ST
          state <= IDLE_ST;
          led_done_r <= 1'b0;
          we_buf2_r <= 1'b0;
        end
      endcase
    end
  end

  // 버퍼 연결
  always @(*) begin
    rdaddr_buf2 = rdaddr_buf2_r;
    din_buf2_r = din_buf2;
    we_buf2 = we_buf2_r;
    wraddr_buf2 = wraddr_buf2_r;
  end

endmodule
