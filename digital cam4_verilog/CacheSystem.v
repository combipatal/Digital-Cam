// VHDL 소스 파일: ed_cache_system.vhd
// 3x3 픽셀 윈도우를 생성하기 위한 캐시 시스템입니다.

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
    wire fsync_temp, rsync_temp;

    // 픽셀 캐시 레지스터 (3개의 라인, 각 라인은 3개의 픽셀)
    reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache1, cache2, cache3;
    
    // --- 서브 모듈 인스턴스화 ---

    // 라인 버퍼: 현재 라인(dout3), 이전 라인(dout2), 2라인 전(dout1) 픽셀 출력
    DoubleFiFOLineBuffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .NO_OF_COLS (NO_OF_COLS)
    ) DoubleLineBuffer (
        .clk        (clk),
        .fsync      (fsync_in),
        .rsync      (rsync_in),
        .pdata_in   (pdata_in),
        .pdata_out1 (dout1),
        .pdata_out2 (dout2),
        .pdata_out3 (dout3)
    );
      
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
  
    // 행/열 카운터 (지연된 동기화 신호 사용)
    Counter #(.n(ROW_BITS)) RowsCounter (
        .clk    (rsync_temp), 
        .en     (fsync_temp), 
        .reset  (~fsync_temp), 
        .output_val (RowsCounterOut)
    );
    
    Counter #(.n(COL_BITS)) ColsCounter (
        .clk    (clk), 
        .en     (rsync_temp), 
        .reset  (~rsync_temp), 
        .output_val (ColsCounterOut)
    );
  
    assign fsync_out = fsync_temp;
    assign rsync_out = rsync_temp;
  
    // 캐시 시프트 로직: 매 클럭마다 픽셀 데이터를 옆으로 한 칸씩 이동
    always @(posedge clk) begin
        // 캐시 1
        cache1[DATA_WIDTH-1:0] <= cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
        cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH] <= cache1[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];
        cache1[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH] <= dout1;
        // 캐시 2
        cache2[DATA_WIDTH-1:0] <= cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
        cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH] <= cache2[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];
        cache2[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH] <= dout2;
        // 캐시 3
        cache3[DATA_WIDTH-1:0] <= cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
        cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH] <= cache3[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];
        cache3[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH] <= dout3;
    end
  
    // 3x3 윈도우 출력 로직: 경계 조건에 따라 픽셀 또는 0을 출력
    always @(*) begin
        if (fsync_temp) begin
            // 픽셀 할당 (default)
            pdata_out1 = cache3[DATA_WIDTH-1:0];
            pdata_out2 = cache3[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
            pdata_out3 = cache3[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];
            pdata_out4 = cache2[DATA_WIDTH-1:0];
            pdata_out5 = cache2[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
            pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];
            pdata_out7 = cache1[DATA_WIDTH-1:0];
            pdata_out8 = cache1[(WINDOW_SIZE-1)*DATA_WIDTH-1 -: DATA_WIDTH];
            pdata_out9 = cache1[(WINDOW_SIZE*DATA_WIDTH)-1 -: DATA_WIDTH];

            // 경계 조건 처리 (0으로 패딩)
            if (RowsCounterOut == 0) begin // Top row
                pdata_out1 = {DATA_WIDTH{1'b0}};
                pdata_out2 = {DATA_WIDTH{1'b0}};
                pdata_out3 = {DATA_WIDTH{1'b0}};
            end else if (RowsCounterOut == NO_OF_ROWS - 1) begin // Bottom row
                pdata_out7 = {DATA_WIDTH{1'b0}};
                pdata_out8 = {DATA_WIDTH{1'b0}};
                pdata_out9 = {DATA_WIDTH{1'b0}};
            end

            if (ColsCounterOut == 0) begin // Left column
                pdata_out1 = {DATA_WIDTH{1'b0}};
                pdata_out4 = {DATA_WIDTH{1'b0}};
                pdata_out7 = {DATA_WIDTH{1'b0}};
            end else if (ColsCounterOut == NO_OF_COLS - 1) begin // Right column
                pdata_out3 = {DATA_WIDTH{1'b0}};
                pdata_out6 = {DATA_WIDTH{1'b0}};
                pdata_out9 = {DATA_WIDTH{1'b0}};
            end
        end else begin
            // 비활성 영역에서는 0 출력
            pdata_out1 = {DATA_WIDTH{1'b0}};
            pdata_out2 = {DATA_WIDTH{1'b0}};
            pdata_out3 = {DATA_WIDTH{1'b0}};
            pdata_out4 = {DATA_WIDTH{1'b0}};
            pdata_out5 = {DATA_WIDTH{1'b0}};
            pdata_out6 = {DATA_WIDTH{1'b0}};
            pdata_out7 = {DATA_WIDTH{1'b0}};
            pdata_out8 = {DATA_WIDTH{1'b0}};
            pdata_out9 = {DATA_WIDTH{1'b0}};
        end
    end
endmodule
