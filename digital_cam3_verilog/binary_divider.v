module binary_divider_ver1 #(
  parameter size = 8
)(
  input wire [size-1:0] A,
  input wire [size-1:0] B,
  output wire [size-1:0] Q,
  output wire [size-1:0] R
);

  // 중간 신호
  reg [size-1:0] Auns, Buns, Quns, Runs;

  // 입력을 부호 없는 값으로 변환
  always @(*) begin
    Auns = A;
    Buns = B;
  end

  // 나눗셈 수행
  always @(*) begin
    Quns = Auns / Buns;
    Runs = Auns % Buns;
  end

  // 결과 출력
  assign Q = Quns;
  assign R = Runs;

endmodule
