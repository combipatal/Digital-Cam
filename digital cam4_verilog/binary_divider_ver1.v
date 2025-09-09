// VHDL 소스 파일: binary_divider.vhd (version 1)
// 조합 논리를 이용한 이진수 나누기 회로

module binary_divider_ver1 #(
    parameter size = 8
) (
    input wire [size-1:0]   A,
    input wire [size-1:0]   B,
    output wire [size-1:0]  Q,  // 몫 (Quotient)
    output wire [size-1:0]  R   // 나머지 (Remainder)
);

    // Verilog의 내장 산술 연산자를 사용하여 나누셈 수행
    assign Q = A / B;
    assign R = A % B;

endmodule
