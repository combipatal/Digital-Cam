// 주소 생성기 - 320x240 해상도 화면을 위한 메모리 주소 생성
module Address_Generator(
  input wire rst_n,          // 활성화 낮음 리셋 신호
  input wire CLK25,          // 25 MHz 클록 신호
  input wire enable,         // 활성화 신호
  input wire vsync,          // 수직 동기화 신호
  output reg [16:0] address  // 생성된 주소 (17비트)
);

  // 내부 신호 선언
  reg [16:0] val;
  
  // 초기화 및 주소 생성 로직
  always @(posedge CLK25) begin
    if (!rst_n) begin        // 리셋 활성화 (낮음)
      val <= 17'd0;
    end else begin
      if (enable) begin
        // 320*240 = 76800 픽셀 메모리 공간 확인
        if (val < 17'd76800)
          val <= val + 1'b1;
      end
      
      // vsync가 0이면 주소 재설정
      if (vsync == 1'b0)
        val <= 17'd0;
    end
  end
  
  // 출력 주소 할당
  always @(*) begin
    address = val;
  end

endmodule