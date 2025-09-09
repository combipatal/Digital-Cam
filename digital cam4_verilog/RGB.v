// VHDL 소스 파일: RGB.vhd
// 12비트 색상 입력을 8비트 R, G, B 채널로 변환합니다.
// 예: R채널의 4비트 입력 {R3, R2, R1, R0}를 {R3, R2, R1, R0, R3, R2, R1, R0}으로 확장합니다.

module RGB (
    input wire [11:0]   Din,        // 12비트 RGB444 입력 데이터
    input wire          Nblank,     // 화면 표시 영역 신호 (active high)
    output wire [7:0]   R, G, B     // 8비트 R, G, B 출력 채널
);

    // Nblank 신호가 '1'일 때 (활성 표시 영역일 때)만 색상 값을 출력하고,
    // 그렇지 않으면 검은색(0)을 출력합니다.
    assign R = (Nblank) ? {Din[11:8], Din[11:8]} : 8'h00;
    assign G = (Nblank) ? {Din[7:4],  Din[7:4]}  : 8'h00;
    assign B = (Nblank) ? {Din[3:0],  Din[3:0]}  : 8'h00;

endmodule