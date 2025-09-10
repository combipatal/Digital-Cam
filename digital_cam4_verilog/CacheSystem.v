// 3x3 윈도우를 생성하기 위한 캐시 시스템
// 비디오 스트림에서 연속된 3개의 라인을 버퍼링하여
// 소벨 필터가 3x3 픽셀 커널 연산을 수행할 수 있도록 데이터를 제공합니다.

module CacheSystem #(
    parameter DATA_WIDTH  = 8,
    parameter WINDOW_SIZE = 3,
    parameter ROW_BITS    = 8,
    parameter COL_BITS    = 9,
    parameter NO_OF_ROWS  = 240,
    parameter NO_OF_COLS  = 320
)(
    input  clk,
    input  fsync_in,
    input  rsync_in,
    input  [DATA_WIDTH-1:0] pdata_in,
    output fsync_out,
    output rsync_out,
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

    // 내부 신호
    wire [ROW_BITS-1:0] RowsCounterOut;
    wire [COL_BITS-1:0] ColsCounterOut;
    wire [DATA_WIDTH-1:0] dout1, dout2, dout3;
    wire fsync_temp, rsync_temp;

    // 픽셀 캐시 레지스터 (3x3 윈도우의 각 라인)
    reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache1, cache2, cache3;

    // --- 모듈 인스턴스 ---

    // 2개의 라인 버퍼를 직렬로 연결하여 총 2라인 분량의 픽셀을 지연시킴
    DoubleFiFOLineBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NO_OF_COLS(NO_OF_COLS)
    ) DoubleLineBuffer_inst (
        .clk(clk),
        .fsync(fsync_in),
        .rsync(rsync_in),
        .pdata_in(pdata_in),
        .pdata_out1(dout1), // 현재 픽셀 (지연 없음)
        .pdata_out2(dout2), // 1 라인 이전 픽셀
        .pdata_out3(dout3)  // 2 라인 이전 픽셀
    );

    // 라인 버퍼의 지연에 맞춰 동기화 신호를 지연시킴
    SyncSignalsDelayer #(
        .ROW_BITS(ROW_BITS)
    ) Delayer_inst (
        .clk(clk),
        .fsync_in(fsync_in),
        .rsync_in(rsync_in),
        .fsync_out(fsync_temp),
        .rsync_out(rsync_temp)
    );

    // 지연된 동기화 신호를 기준으로 행(Row)과 열(Column) 카운터 동작
    Counter #( .N(ROW_BITS) ) RowsCounter (
        .clk(rsync_temp),
        .en(fsync_temp),
        .reset(~fsync_temp), // Active Low reset
        .output_val(RowsCounterOut)
    );
    Counter #( .N(COL_BITS) ) ColsCounter (
        .clk(clk),
        .en(rsync_temp),
        .reset(~rsync_temp), // Active Low reset
        .output_val(ColsCounterOut)
    );

    // 최종 출력 동기화 신호
    assign fsync_out = fsync_temp;
    assign rsync_out = rsync_temp;

    // --- 3x3 윈도우 생성 로직 ---

    // 매 클럭마다 3개의 캐시 레지스터를 시프트하여 3x3 윈도우를 구성
    always @(posedge clk) begin
        // z7 -> z4 -> z1, z8 -> z5 -> z2, z9 -> z6 -> z3
        cache1 <= {cache1[(WINDOW_SIZE*DATA_WIDTH)-1 -: (WINDOW_SIZE-1)*DATA_WIDTH], dout1};
        cache2 <= {cache2[(WINDOW_SIZE*DATA_WIDTH)-1 -: (WINDOW_SIZE-1)*DATA_WIDTH], dout2};
        cache3 <= {cache3[(WINDOW_SIZE*DATA_WIDTH)-1 -: (WINDOW_SIZE-1)*DATA_WIDTH], dout3};
    end
    
    // [오류 수정] Verilog의 표준 continuous assignment 문법인 'assign'을 사용합니다.
    // 'logic is_first_row = ...'는 SystemVerilog 문법입니다.
    wire is_first_row = (RowsCounterOut == 0);
    wire is_last_row  = (RowsCounterOut == NO_OF_ROWS - 1);
    wire is_first_col = (ColsCounterOut == 2'd1); // 2클럭 지연 고려
    wire is_last_col  = (ColsCounterOut == NO_OF_COLS - 1);
    
    // 현재 윈도우의 위치(가장자리/내부)에 따라 9개의 출력 픽셀 값을 결정
    always @(*) begin
        if (fsync_temp) begin
            // 윈도우의 각 위치에 해당하는 픽셀 데이터
            // cache[7:0]   = z1, z2, z3
            // cache[15:8]  = z4, z5, z6
            // cache[23:16] = z7, z8, z9
            
            // pdata_out7, 8, 9 (가장 오래된 라인)
            pdata_out7 = (is_first_row || is_first_col) ? 0 : cache1[DATA_WIDTH-1:0];
            pdata_out8 = (is_first_row) ? 0 : cache1[2*DATA_WIDTH-1:DATA_WIDTH];
            pdata_out9 = (is_first_row || is_last_col)  ? 0 : cache1[3*DATA_WIDTH-1:2*DATA_WIDTH];

            // pdata_out4, 5, 6 (중간 라인)
            pdata_out4 = (is_first_col) ? 0 : cache2[DATA_WIDTH-1:0];
            pdata_out5 = cache2[2*DATA_WIDTH-1:DATA_WIDTH]; // 항상 중앙 픽셀
            pdata_out6 = (is_last_col)  ? 0 : cache2[3*DATA_WIDTH-1:2*DATA_WIDTH];

            // pdata_out1, 2, 3 (가장 최신 라인)
            pdata_out1 = (is_last_row || is_first_col) ? 0 : cache3[DATA_WIDTH-1:0];
            pdata_out2 = (is_last_row) ? 0 : cache3[2*DATA_WIDTH-1:DATA_WIDTH];
            pdata_out3 = (is_last_row || is_last_col)  ? 0 : cache3[3*DATA_WIDTH-1:2*DATA_WIDTH];
        end else begin
            // 비디오 활성 영역이 아닐 경우 모든 출력을 0으로
            pdata_out1 = 0; pdata_out2 = 0; pdata_out3 = 0;
            pdata_out4 = 0; pdata_out5 = 0; pdata_out6 = 0;
            pdata_out7 = 0; pdata_out8 = 0; pdata_out9 = 0;
        end
    end

endmodule

