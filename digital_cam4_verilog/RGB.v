// RGB444 포맷을 RGB888 포맷으로 변환하는 모듈
// VGA 출력에 사용됩니다.

module RGB (
    input [11:0] Din,     // 입력 데이터 (RGB444)
    input Nblank,         // 화면 표시 유효 구간 신호
    output [7:0] R, G, B  // 출력 데이터 (RGB888)
);

    // Nblank 신호가 '1'일 때 (유효 구간) 데이터를 변환하고,
    // 아닐 때는 검은색(0)을 출력합니다.
    // 각 4비트 채널을 복제하여 8비트로 확장합니다 (예: '1101' -> '11011101').
    assign R = Nblank ? {Din[11:8], Din[11:8]} : 8'h00;
    assign G = Nblank ? {Din[7:4],  Din[7:4]}  : 8'h00;
    assign B = Nblank ? {Din[3:0],  Din[3:0]}  : 8'h00;

endmodule
 