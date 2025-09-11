// 이진 나눗셈기 - 직접적인 나눗셈 연산 구현
module binary_divider_ver1 #(
  parameter size = 8
)(
  input wire [size-1:0] A,      // 나눠질 수 (피제수)
  input wire [size-1:0] B,      // 나누는 수 (제수)
  output wire [size-1:0] Q,     // 몫
  output wire [size-1:0] R      // 나머지
);

  // 내부 신호 선언 - unsigned 타입 변환을 위한 레지스터
  wire [size-1:0] Auns, Buns;
  wire [size-1:0] Quns, Runs;
  
  // 입력을 부호없는 타입으로 변환
  assign Auns = A;
  assign Buns = B;
  
  // 나눗셈을 시프트 연산으로 대체 (B가 3인 경우)
  // 3으로 나누기 = (A/4 + A/16 + A/64 + ...) 근사값
  // A/3 ≈ (A>>2) + (A>>4) + (A>>6) + (A>>8)
  assign Quns = (B == 8'h03) ? ((Auns >> 2) + (Auns >> 4) + (Auns >> 6) + (Auns >> 8)) : (Auns / Buns);
  
  // 나머지 연산 - 나눗셈 결과로 계산 (R = A - Q * B)
  assign Runs = (B == 8'h03) ? (Auns - (Quns * Buns)) : (Auns % Buns);
  
  // 결과 할당
  assign Q = Quns;
  assign R = Runs;

endmodule