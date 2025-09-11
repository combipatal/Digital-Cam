// RGB 모듈 - 픽셀 데이터를 RGB 형식으로 변환
module RGB(
  input wire [11:0] Din,     // 12비트 픽셀 데이터
  input wire Nblank,         // 화면 표시 영역 신호
  output wire [7:0] R,       // 적색 출력(8비트)
  output wire [7:0] G,       // 녹색 출력(8비트)
  output wire [7:0] B        // 청색 출력(8비트)
);

  // 각 채널별 데이터 추출 및 확장
  // 4비트 입력을 8비트로 확장 (상위 4비트를 복제)
  assign R = Nblank ? {Din[11:8], 4'b1111} : 8'h00;
  assign G = Nblank ? {Din[7:4], 4'b1111} : 8'h00;
  assign B = Nblank ? {Din[3:0], 4'b1111} : 8'h00;

endmodule