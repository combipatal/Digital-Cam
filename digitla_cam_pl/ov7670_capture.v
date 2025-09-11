// OV7670 카메라 캡처 모듈 - 프레임 데이터를 캡처하고 RAM에 저장
module ov7670_capture(
  input wire pclk,
  input wire vsync,
  input wire href,     // HS 신호로 사용됨 (내부적으로는 href라는 이름 유지)
  input wire [7:0] d,
  output wire [16:0] addr,
  output wire [11:0] dout,
  output wire we,
  output wire end_of_frame
);

  // 내부 신호
  reg [15:0] d_latch;
  reg [16:0] address;
  reg [1:0] line;
  reg [6:0] href_last;
  reg we_reg;
  reg end_of_frame_reg;
  reg href_hold;
  
  // 동기화된 입력 신호
  reg latched_vsync;
  reg latched_href;
  reg [7:0] latched_d;
  
  // 출력 신호 할당
  assign addr = address;
  assign we = we_reg;
  assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};
  assign end_of_frame = end_of_frame_reg;
  
  // 캡처 프로세스
  always @(posedge pclk) begin
    // 쓰기 활성화시 주소 증가
    if (we_reg)
      address <= address + 1'b1;
      
    // href 상승 에지 감지 (라인 시작)
    if (href_hold == 1'b0 && latched_href == 1'b1) begin
      case (line)
        2'b00: line <= 2'b01;
        2'b01: line <= 2'b10;
        2'b10: line <= 2'b11;
        default: line <= 2'b00;
      endcase
    end
    href_hold <= latched_href;
    
    // 카메라에서 데이터 캡처 (12비트 RGB)
    if (latched_href)
      d_latch <= {d_latch[7:0], latched_d};
    we_reg <= 1'b0;
    
    // 새 화면이 시작되는지 확인
    if (latched_vsync) begin
      address <= 17'd0;
      href_last <= 7'd0;
      line <= 2'd0;
      end_of_frame_reg <= 1'b1;
    end else begin
      // 픽셀을 캡처해야 할 때 쓰기 활성화
      if (href_last[2]) begin
        if (line[1])
          we_reg <= 1'b1;
        href_last <= 7'd0;
      end else begin
        href_last <= {href_last[5:0], latched_href};
      end
      end_of_frame_reg <= 1'b0;
    end
  end
  
  // 하강 에지에서 입력 신호 래치
  always @(negedge pclk) begin
    latched_d <= d;
    latched_href <= href;
    latched_vsync <= vsync;
  end

endmodule