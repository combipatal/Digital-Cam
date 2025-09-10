// 이중 FIFO 라인 버퍼 모듈
// FIFOLineBuffer 두 개를 직렬로 연결하여 총 두 라인의 지연을 생성합니다.
// 3x3 윈도우 처리를 위해 현재 라인과 이전 두 라인의 데이터에 접근할 수 있게 합니다.

module DoubleFiFOLineBuffer #(
    parameter DATA_WIDTH = 8,   // 픽셀 데이터 비트 폭
    parameter NO_OF_COLS = 320  // 한 라인의 컬럼(픽셀) 수
)(
    input clk,
    input fsync,
    input rsync,
    input      [DATA_WIDTH-1:0] pdata_in,   // 입력 픽셀 (현재 라인)
    output     [DATA_WIDTH-1:0] pdata_out1, // 지연 없는 출력 (pdata_in과 동일)
    output     [DATA_WIDTH-1:0] pdata_out2, // 1라인 지연된 출력 (이전 라인)
    output     [DATA_WIDTH-1:0] pdata_out3  // 2라인 지연된 출력 (2라인 전)
);

    // pdata_out1은 입력 데이터를 그대로 통과시킵니다.
    assign pdata_out1 = pdata_in;

    // 첫 번째 라인 버퍼 인스턴스
    FIFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) LineBuffer1 (
        .clk(clk),
        .fsync(fsync),
        .rsync(rsync),
        .pdata_in(pdata_in),
        .pdata_out(pdata_out2) // 첫 번째 버퍼의 출력이 pdata_out2가 됨
    );

    // 두 번째 라인 버퍼 인스턴스
    FIFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) LineBuffer2 (
        .clk(clk),
        .fsync(fsync),
        .rsync(rsync),
        .pdata_in(pdata_out2), // 첫 번째 버퍼의 출력을 입력으로 받음
        .pdata_out(pdata_out3)  // 두 번째 버퍼의 출력이 pdata_out3가 됨
    );

endmodule
