// FIFO 라인 버퍼 모듈
// 한 라인의 픽셀 데이터를 저장하여 한 라인만큼 지연시키는 역할을 합니다.
// 간단한 시프트 레지스터 기반으로 구현되었습니다.

module FIFOLineBuffer #(
    parameter DATA_WIDTH = 8,   // 픽셀 데이터의 비트 폭
    parameter NO_OF_COLS = 320  // 한 라인의 컬럼(픽셀) 수
)(
    input clk,                  // 클럭
    input fsync,                // 프레임 동기화 (V-sync)
    input rsync,                // 라인 동기화 (H-sync)
    input [DATA_WIDTH-1:0] pdata_in,  // 입력 픽셀 데이터
    output [DATA_WIDTH-1:0] pdata_out // 지연된 출력 픽셀 데이터
);

    // NO_OF_COLS 깊이를 갖는 시프트 레지스터
    reg [DATA_WIDTH-1:0] shift_reg [0:NO_OF_COLS-1];
    integer i;

    // 클럭에 동기화하여 시프트 동작 수행
    always @(posedge clk) begin
        // rsync가 high일 때 (활성 비디오 구간) 데이터 시프트
        if (rsync) begin
            // 새로운 데이터를 레지스터의 시작 부분에 입력
            shift_reg[0] <= pdata_in;
            // 나머지 데이터를 한 칸씩 뒤로 이동
            for (i = 0; i < NO_OF_COLS - 1; i = i + 1) begin
                shift_reg[i+1] <= shift_reg[i];
            end
        end
    end

    // 레지스터의 가장 마지막 값을 출력
    assign pdata_out = shift_reg[NO_OF_COLS-1];

endmodule
