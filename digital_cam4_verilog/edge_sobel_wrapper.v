    // 소벨(Sobel) 에지 검출 필터 래퍼 모듈
    // CacheSystem을 사용하여 3x3 픽셀 윈도우를 생성하고,
    // 이를 edge_sobel 커널 모듈에 전달하여 에지 검출을 수행합니다.

    // 참고: 이 파일은 'edge_sobel' 모듈의 구현을 포함하지 않습니다.
    // 'edge_sobel.v' 파일이 별도로 프로젝트에 포함되어야 합니다.

    module edge_sobel_wrapper #(
        parameter DATA_WIDTH = 8
    )(
        input clk,
        input fsync_in,
        input rsync_in,
        input [DATA_WIDTH-1:0] pdata_in,
        output fsync_out,
        output rsync_out,
        output [DATA_WIDTH-1:0] pdata_out
    );

        // 3x3 윈도우 출력을 위한 내부 와이어
        wire [DATA_WIDTH-1:0] pdata_int1, pdata_int2, pdata_int3,
                            pdata_int4, pdata_int5, pdata_int6,
                            pdata_int7, pdata_int8, pdata_int9;

        // 지연된 동기화 신호를 위한 내부 와이어
        wire fsynch_int, rsynch_int;

        // 3x3 윈도우 캐시 시스템 인스턴스
        CacheSystem #(
            .DATA_WIDTH(DATA_WIDTH),
            .WINDOW_SIZE(3),
            .ROW_BITS(8),
            .COL_BITS(9),
            .NO_OF_ROWS(240),
            .NO_OF_COLS(320)
        ) Inst_CacheSystem (
            .clk(clk),
            .fsync_in(fsync_in),
            .rsync_in(rsync_in),
            .pdata_in(pdata_in),
            .fsync_out(fsynch_int),
            .rsync_out(rsynch_int),
            .pdata_out1(pdata_int1),
            .pdata_out2(pdata_int2),
            .pdata_out3(pdata_int3),
            .pdata_out4(pdata_int4),
            .pdata_out5(pdata_int5),
            .pdata_out6(pdata_int6),
            .pdata_out7(pdata_int7),
            .pdata_out8(pdata_int8),
            .pdata_out9(pdata_int9)
        );

        // 실제 소벨 필터 연산을 수행하는 커널 모듈 인스턴스
        edge_sobel_pipelined #(
            .DATA_WIDTH(DATA_WIDTH)
        ) krnl (
            .pclk_i(clk),
            .fsync_i(fsynch_int),
            .rsync_i(rsynch_int),
            .pData1(pdata_int1),
            .pData2(pdata_int2),
            .pData3(pdata_int3),
            .pData4(pdata_int4),
            .pData5(pdata_int5),
            .pData6(pdata_int6),
            .pData7(pdata_int7),
            .pData8(pdata_int8),
            .pData9(pdata_int9),
            .fsync_o(fsync_out),
            .rsync_o(rsync_out),
            .pdata_o(pdata_out)
        );

    endmodule
