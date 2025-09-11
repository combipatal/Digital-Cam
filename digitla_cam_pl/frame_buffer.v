// 프레임 버퍼 - 320x240 해상도의 픽셀 데이터 저장
module frame_buffer(
  input wire [11:0] data,        // 입력 픽셀 데이터
  input wire [16:0] rdaddress,   // 읽기 주소
  input wire rdclock,            // 읽기 클록
  input wire [16:0] wraddress,   // 쓰기 주소
  input wire wrclock,            // 쓰기 클록
  input wire wren,               // 쓰기 활성화
  output wire [11:0] q           // 출력 픽셀 데이터
);

  // 내부 신호
  wire [11:0] q_top;
  wire [11:0] q_bottom;
  reg wren_top;
  reg wren_bottom;
  
  // 하위 65536 주소를 위한 버퍼
  my_frame_buffer_15to0 Inst_buffer_top(
    .data(data),
    .rdaddress(rdaddress[15:0]),
    .rdclock(rdclock),
    .wraddress(wraddress[15:0]),
    .wrclock(wrclock),
    .wren(wren_top),
    .q(q_top)
  );
  
  // 상위 주소(65536~76800)를 위한 버퍼
  my_frame_buffer_15to0 Inst_buffer_bottom(
    .data(data),
    .rdaddress(rdaddress[15:0]),
    .rdclock(rdclock),
    .wraddress(wraddress[15:0]),
    .wrclock(wrclock),
    .wren(wren_bottom),
    .q(q_bottom)
  );
  
  // 쓰기 활성화 신호 제어
  always @(*) begin
    case (wraddress[16])
      1'b0: begin
        wren_top = wren;
        wren_bottom = 1'b0;
      end
      1'b1: begin
        wren_top = 1'b0;
        wren_bottom = wren;
      end
      default: begin
        wren_top = 1'b0;
        wren_bottom = 1'b0;
      end
    endcase
  end
  
  // 읽기 데이터 선택
  assign q = (rdaddress[16] == 1'b0) ? q_top : 
             (rdaddress[16] == 1'b1) ? q_bottom : 12'b0;

endmodule