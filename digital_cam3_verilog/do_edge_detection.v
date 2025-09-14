module do_edge_detection(
  // 제어
  input wire rst_i,
  input wire clk_i,  // 25 MHz
  input wire enable_sobel_filter,
  output wire led_sobel_done,
  // 프레임 버퍼 2에서 이미지 데이터를 읽기 위한 연결
  output reg [16:0] rdaddr_buf2,
  input wire [11:0] din_buf2,
  // 처리 후 버퍼 2에 쓰기 위한 연결
  output reg [16:0] wraddr_buf2,
  output wire [11:0] dout_buf2,
  output reg we_buf2
);

  // 상태 정의
  localparam START_SOBEL_FILTER_ST = 3'b000;
  localparam GET_PIXEL_DATA_ST     = 3'b001;
  localparam STALL_1_CYCLE_ST      = 3'b010;
  localparam STALL_2_CYCLE_ST      = 3'b011;
  localparam SEND_PIXEL_DATA_ST    = 3'b100;
  localparam DONE_ST               = 3'b101;
  localparam IDLE_ST               = 3'b110;

  // 상수
  localparam [16:0] NUM_PIXELS = 17'd76799;

  // 신호 선언
  reg led_done_r = 1'b0;
  reg [16:0] rdaddr_buf2_r = 17'b0;
  reg [7:0] din_buf2_r;
  reg [16:0] wraddr_buf2_r = 17'b0;
  reg [7:0] dout_buf2_r = 8'b0;
  reg we_buf2_r = 1'b0;
  
  reg [16:0] rd_cntr = 17'b0;
  reg [16:0] wr_cntr = 17'b0;
  reg [2:0] state = IDLE_ST;
  
  // Sobel 필터에 필요한 더미 동기화 신호
  reg hsync_dummy;
  reg vsync_dummy;
  wire hsync_delayed;
  wire vsync_delayed;
  reg [8:0] ColsCounter = 9'b0;
  reg clk_div2 = 1'b0;
  
  // 출력 할당
  assign led_sobel_done = led_done_r;

  // 버퍼 2에서 읽기
  wire [7:0] sobel_input = {din_buf2[3:0], 4'b0000}; // 흑백 이미지로 작업
  wire [7:0] sobel_output;

  // Sobel 필터 인스턴스
  edge_sobel_wrapper #(
    .DATA_WIDTH(8)
  ) Inst_edge_sobel_wrapper (
    .clk(clk_div2),
    .fsync_in(vsync_dummy),
    .rsync_in(hsync_dummy),
    .pdata_in(din_buf2_r),
    .fsync_out(vsync_delayed),
    .rsync_out(hsync_delayed),
    .pdata_out(sobel_output)
  );

  // 클럭 2분주
  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      clk_div2 <= 1'b0;
    end else begin
      clk_div2 <= ~clk_div2;
    end
  end

  // 출력 데이터 형식 변환
  assign dout_buf2 = {dout_buf2_r[7:4], dout_buf2_r[7:4], dout_buf2_r[7:4]};

  // 메인 상태 머신
  always @(posedge clk_i) begin
    if (rst_i) begin
      state <= IDLE_ST;
      led_done_r <= 1'b0;
      rd_cntr <= 17'b0;
      wr_cntr <= 17'b0;
      we_buf2_r <= 1'b0;
      rdaddr_buf2_r <= 17'b0;
      wraddr_buf2_r <= 17'b0;
      vsync_dummy <= 1'b0;
      hsync_dummy <= 1'b0;
      ColsCounter <= 9'b0;
    end
    else if (enable_sobel_filter == 1'b1 && state == IDLE_ST) begin
      state <= START_SOBEL_FILTER_ST;
      led_done_r <= 1'b0;
      rd_cntr <= 17'b0;
      wr_cntr <= 17'b0;
      we_buf2_r <= 1'b1;
      rdaddr_buf2_r <= 17'b0;
      wraddr_buf2_r <= 17'b0;
      vsync_dummy <= 1'b1;
      hsync_dummy <= 1'b0;
      ColsCounter <= 9'b0;
    end
    else begin
      case (state)
        START_SOBEL_FILTER_ST: begin
          state <= GET_PIXEL_DATA_ST;
          led_done_r <= 1'b0;
          rd_cntr <= 17'b0;
          wr_cntr <= 17'b0;
          we_buf2_r <= 1'b1;
          rdaddr_buf2_r <= 17'b0;
          wraddr_buf2_r <= 17'b0;
          vsync_dummy <= 1'b1;
          hsync_dummy <= 1'b0;
          ColsCounter <= 9'b0;
        end
        
        GET_PIXEL_DATA_ST: begin
          state <= SEND_PIXEL_DATA_ST;
          rdaddr_buf2_r <= rdaddr_buf2_r + 1;
          if (rd_cntr > 323) begin
            wraddr_buf2_r <= wraddr_buf2_r + 1;
            wr_cntr <= wr_cntr + 1;
          end else begin
            wraddr_buf2_r <= 17'b0;
            wr_cntr <= 17'b0;
          end
        end
        
        SEND_PIXEL_DATA_ST: begin
          if (wr_cntr < NUM_PIXELS) begin
            rd_cntr <= rd_cntr + 1;
            if (ColsCounter < 319) begin
              ColsCounter <= ColsCounter + 1;
              hsync_dummy <= 1'b1;
              state <= GET_PIXEL_DATA_ST;
            end else begin
              ColsCounter <= 9'b0;
              hsync_dummy <= 1'b0;
              state <= STALL_1_CYCLE_ST;
            end
          end else begin
            state <= DONE_ST;
          end
        end
        
        STALL_1_CYCLE_ST: begin
          state <= STALL_2_CYCLE_ST;
        end
        
        STALL_2_CYCLE_ST: begin
          state <= GET_PIXEL_DATA_ST;
          hsync_dummy <= 1'b1;
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
    din_buf2_r = sobel_input;
    dout_buf2_r = sobel_output;
    we_buf2 = we_buf2_r;
    wraddr_buf2 = wraddr_buf2_r;
  end

endmodule
