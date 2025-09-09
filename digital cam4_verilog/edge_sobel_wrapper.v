// VHDL 소스 파일: ed_edge_sobel_wrapper.vhd
//
// Sobel 필터 구현을 위한 래퍼 모듈입니다.
// 이 모듈은 그레이스케일 이미지를 가정하며, 각 픽셀은 8비트로 표현됩니다.

module edge_sobel_wrapper #(
    parameter DATA_WIDTH = 8
) (
    input wire                  clk,
    input wire                  fsync_in,
    input wire                  rsync_in,
    input wire [DATA_WIDTH-1:0] pdata_in,
    output wire                 fsync_out,
    output wire                 rsync_out,
    output wire [DATA_WIDTH-1:0] pdata_out
);

    // 내부 연결 신호
    wire [DATA_WIDTH-1:0] pdata_int1, pdata_int2, pdata_int3,
                          pdata_int4, pdata_int5, pdata_int6,
                          pdata_int7, pdata_int8, pdata_int9;
    wire fsynch_int, rsynch_int;

    // CacheSystem 인스턴스화:
    // 픽셀 스트림으로부터 3x3 윈도우(pdata_int1 ~ pdata_int9)를 생성합니다.
    CacheSystem #(
        .DATA_WIDTH (DATA_WIDTH),
        .WINDOW_SIZE(3),
        .ROW_BITS   (8),
        .COL_BITS   (9),
        .NO_OF_ROWS (240),
        .NO_OF_COLS (320)
    ) cache_system_inst (
        .clk        (clk),
        .fsync_in   (fsync_in),
        .rsync_in   (rsync_in),
        .pdata_in   (pdata_in),
        .fsync_out  (fsynch_int),
        .rsync_out  (rsynch_int),
        .pdata_out1 (pdata_int1),
        .pdata_out2 (pdata_int2),
        .pdata_out3 (pdata_int3),
        .pdata_out4 (pdata_int4),
        .pdata_out5 (pdata_int5),
        .pdata_out6 (pdata_int6),
        .pdata_out7 (pdata_int7),
        .pdata_out8 (pdata_int8),
        .pdata_out9 (pdata_int9)
    );

    // edge_sobel (커널) 인스턴스화:
    // 3x3 윈도우를 입력받아 Sobel 연산을 수행하고 최종 픽셀 값을 출력합니다.
    edge_sobel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) sobel_kernel_inst (
        .pclk_i  (clk),
        .fsync_i (fsynch_int),
        .rsync_i (rsynch_int),
        .pData1  (pdata_int1),
        .pData2  (pdata_int2),
        .pData3  (pdata_int3),
        .pData4  (pdata_int4),
        .pData5  (pdata_int5),
        .pData6  (pdata_int6),
        .pData7  (pdata_int7),
        .pData8  (pdata_int8),
        .pData9  (pdata_int9),
        .fsync_o (fsync_out),
        .rsync_o (rsync_out),
        .pdata_o (pdata_out)
    );

endmodule
