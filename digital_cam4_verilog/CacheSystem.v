// VHDL 소스 파일: ed_cache_system.vhd
// 3x3 픽셀 윈도우를 생성하기 위한 캐시 시스템입니다.
// 잘못된 모듈 호출(DoubleFiFOLineBuffer)을 FIFOLineBuffer 2개로 수정하고 포트 이름을 바로잡았습니다.

module CacheSystem #(
    parameter DATA_WIDTH  = 8,
    parameter WINDOW_SIZE = 3,
    parameter ROW_BITS    = 8,
    parameter COL_BITS    = 9,
    parameter NO_OF_ROWS  = 240,
    parameter NO_OF_COLS  = 320
) (
    input wire                  clk,
    input wire                  fsync_in,
    input wire                  rsync_in,
    input wire [DATA_WIDTH-1:0] pdata_in,
    output wire                 fsync_out,
    output wire                 rsync_out,
    output reg [DATA_WIDTH-1:0] pdata_out1,
    output reg [DATA_WIDTH-1:0] pdata_out2,
    output reg [DATA_WIDTH-1:0] pdata_out3,
    output reg [DATA_WIDTH-1:0] pdata_out4,
    output reg [DATA_WIDTH-1:0] pdata_out5,
    output reg [DATA_WIDTH-1:0] pdata_out6,
    output reg [DATA_WIDTH-1:0] pdata_out7,
    output reg [DATA_WIDTH-1:0] pdata_out8,
    output reg [DATA_WIDTH-1:0] pdata_out9
);

    // 내부 신호 선언
    wire [ROW_BITS-1:0] RowsCounterOut;
    wire [COL_BITS-1:0] ColsCounterOut;
    wire [DATA_WIDTH-1:0] dout1, dout2, dout3;
    wire [DATA_WIDTH-1:0] line_buffer1_out;
    wire fsync_temp, rsync_temp;

    // 픽셀 캐시 레지스터
    reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache1, cache2, cache3;

    // --- 서브 모듈 인스턴스화 ---

    // 라인 버퍼 1: 한 라인 지연된 데이터 출력
    FIFOLineBuffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .NO_OF_COLS (NO_OF_COLS)
    ) LineBuffer1 (
        .clk       (clk),
        .fsync     (fsync_in),
        .rsync     (rsync_in),
        .pdata_in  (pdata_in),
        .pdata_out (line_buffer1_out)
    );

    // 라인 버퍼 2: 두 라인 지연된 데이터 출력
    FIFOLineBuffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .NO_OF_COLS (NO_OF_COLS)
    ) LineBuffer2 (
        .clk       (clk),
        .fsync     (fsync_in),
        .rsync     (rsync_in),
        .pdata_in  (line_buffer1_out), // 첫 번째 버퍼의 출력을 입력으로 받음
        .pdata_out (dout1)              // 2라인 전 픽셀 (pdata_out1 -> dout1)
    );

    assign dout2 = line_buffer1_out; // 1라인 전 픽셀
    assign dout3 = pdata_in;         // 현재 픽셀

    // 동기화 신호 지연기
    SyncSignalsDelayer #(
        .ROW_BITS (ROW_BITS)
    ) Delayer (
        .clk       (clk),
        .fsync_in  (fsync_in),
        .rsync_in  (rsync_in),
        .fsync_out (fsync_temp),
        .rsync_out (rsync_temp)
    );

    // 행/열 카운터
    Counter #(.n(ROW_BITS)) RowsCounter (
        .clk    (rsync_temp),
        .en     (fsync_temp),
        .reset  (~fsync_temp), // Active Low Reset
        .output_val (RowsCounterOut) // <<-- ERROR FIX: Port name corrected
    );

    Counter #(.n(COL_BITS)) ColsCounter (
        .clk    (clk),
        .en     (rsync_temp),
        .reset  (~rsync_temp), // Active Low Reset
        .output_val (ColsCounterOut) // <<-- ERROR FIX: Port name corrected
    );

    assign fsync_out = fsync_temp;
    assign rsync_out = rsync_temp;

    // 캐시 시프트 로직
    always @(posedge clk) begin
        cache1 <= {cache1[(WINDOW_SIZE*DATA_WIDTH)-DATA_WIDTH-1:0], dout1};
        cache2 <= {cache2[(WINDOW_SIZE*DATA_WIDTH)-DATA_WIDTH-1:0], dout2};
        cache3 <= {cache3[(WINDOW_SIZE*DATA_WIDTH)-DATA_WIDTH-1:0], dout3};
    end

    // 3x3 윈도우 출력 로직
    always @(*) begin
        if (fsync_temp) begin
            // 픽셀 할당 (default)
            pdata_out1 = cache1[DATA_WIDTH-1:0];
            pdata_out2 = cache1[2*DATA_WIDTH-1:DATA_WIDTH];
            pdata_out3 = cache1[3*DATA_WIDTH-1:2*DATA_WIDTH];
            pdata_out4 = cache2[DATA_WIDTH-1:0];
            pdata_out5 = cache2[2*DATA_WIDTH-1:DATA_WIDTH];
            pdata_out6 = cache2[3*DATA_WIDTH-1:2*DATA_WIDTH];
            pdata_out7 = cache3[DATA_WIDTH-1:0];
            pdata_out8 = cache3[2*DATA_WIDTH-1:DATA_WIDTH];
            pdata_out9 = cache3[3*DATA_WIDTH-1:2*DATA_WIDTH];

            // 경계 조건 처리
            if (RowsCounterOut == 0 || RowsCounterOut == NO_OF_ROWS - 1 || ColsCounterOut == 0 || ColsCounterOut == NO_OF_COLS - 1) begin
                 pdata_out1 = 0; pdata_out2 = 0; pdata_out3 = 0;
                 pdata_out4 = 0; pdata_out5 = 0; pdata_out6 = 0;
                 pdata_out7 = 0; pdata_out8 = 0; pdata_out9 = 0;
            end
        end else begin
            pdata_out1 = 0; pdata_out2 = 0; pdata_out3 = 0;
            pdata_out4 = 0; pdata_out5 = 0; pdata_out6 = 0;
            pdata_out7 = 0; pdata_out8 = 0; pdata_out9 = 0;
        end
    end
endmodule
