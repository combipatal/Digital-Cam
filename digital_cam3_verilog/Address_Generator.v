module Address_Generator(
  input wire rst_i,
  input wire CLK25,
  input wire enable,
  input wire vsync,
  output reg [16:0] address
);

  // 초기 신호 선언
  reg [16:0] val = 17'b0;

  // 출력 할당
  always @(*) begin
    address = val;
  end

  // 주소 생성 프로세스
  always @(posedge CLK25) begin
    if (rst_i) begin
      val <= 17'b0;
    end else begin
      if (enable) begin
        if (val < 320*240) begin
          val <= val + 1;
        end
      end
      
      if (vsync == 1'b0) begin
        val <= 17'b0;
      end
    end
  end

endmodule
