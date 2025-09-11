// 캐시 시스템 모듈 - 이미지 처리를 위한 픽셀 데이터 캐싱
module CacheSystem #(
  parameter DATA_WIDTH = 8,
  parameter WINDOW_SIZE = 3,
  parameter ROW_BITS = 8,    // 640x480의 경우 9
  parameter COL_BITS = 9,    // 640x480의 경우 10
  parameter NO_OF_ROWS = 240,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
  input wire rst_n,          // 활성화 낮음 리셋
  input wire fsync_in,
  input wire rsync_in,
  input wire [DATA_WIDTH-1:0] pdata_in,
  output wire fsync_out,
  output wire rsync_out,
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
  
  // 픽셀 요소 캐시
  // |--------------------------------|
  // | z9-z6-z3 | z8-z5-z2 | z7-z4-z1 |
  // |--------------------------------|
  // 23       16|15       8|7         0
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache1;
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache2;
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache3;
  
  // 이중 라인 버퍼 인스턴스
  DoubleFIFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) DoubleLineBuffer (
    .clk(clk),
    .rst_n(rst_n),
    .fsync(fsync_in),
    .rsync(rsync_in),
    .pdata_in(pdata_in),
    .pdata_out1(dout1),
    .pdata_out2(dout2),
    .pdata_out3(dout3)
  );
  
  // 동기화 신호 지연기 인스턴스
  SyncSignalsDelayer #(
    .ROW_BITS(ROW_BITS)
  ) Delayer (
    .clk(clk),
	 .rst_n(rst_n), 
    .fsync_in(fsync_in),
    .rsync_in(rsync_in),
    .fsync_out(fsync_temp),
    .rsync_out(rsync_temp)
  );
  
  // 행 카운터 (지연된 동기화 신호 사용)
  Counter #(.n(8)) RowsCounter (
    .clk(rsync_temp),
    .en(fsync_temp),
    .rst_n(!fsync_temp),  // 활성화 낮음으로 유지되어야 하지만 이 경우 높음으로 동작
    .output_count(RowsCounterOut)
  );
  
  // 열 카운터
  Counter #(.n(9)) ColsCounter (
    .clk(clk),
    .en(rsync_temp),
    .rst_n(!rsync_temp),  // 활성화 낮음으로 유지되어야 하지만 이 경우 높음으로 동작
    .output_count(ColsCounterOut)
  );
  
  // 출력 신호 연결
  assign fsync_out = fsync_temp;
  assign rsync_out = rsync_temp;
  
  // 시프팅 프로세스 - 픽셀 데이터를 캐시에 저장하고 시프트
  always @(posedge clk) begin
    if (!rst_n) begin
      cache1 <= {(WINDOW_SIZE*DATA_WIDTH){1'b0}};
      cache2 <= {(WINDOW_SIZE*DATA_WIDTH){1'b0}};
      cache3 <= {(WINDOW_SIZE*DATA_WIDTH){1'b0}};
    end else begin
      // 중간 부분 픽셀을 낮은 부분으로 복사
      cache1[DATA_WIDTH-1:0] <= cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
      cache2[DATA_WIDTH-1:0] <= cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
      cache3[DATA_WIDTH-1:0] <= cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
      
      // 높은 부분 픽셀을 중간 부분으로 복사
      cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      
      // RAM 출력을 캐시의 높은 부분에 넣기
      cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout1;
      cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout2;
      cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout3;
    end
  end
  
  // 픽셀 출력 프로세스 - 위치에 따라 적절한 픽셀 값 선택
  always @(*) begin
    if (fsync_temp) begin
      // 위치에 따라 다른 픽셀 출력 로직 (9개의 픽셀 창)
      if (RowsCounterOut == 8'h00 && ColsCounterOut == 9'h000) begin
        // 첫 번째 픽셀 위치
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
        pdata_out9 = cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut == 8'h00 && ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        // 첫 행의 나머지 픽셀
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = cache1[DATA_WIDTH-1:0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut == 8'h00 && ColsCounterOut == 9'h13F) begin
        // 첫 행의 마지막 픽셀
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = cache1[DATA_WIDTH-1:0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && ColsCounterOut == 9'h000) begin
        // 중간 행의 첫 번째 픽셀
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && 
               ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        // 중간 행/열의 픽셀
        pdata_out1 = cache3[DATA_WIDTH-1:0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = cache1[DATA_WIDTH-1:0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && ColsCounterOut == 9'h13F) begin
        // 중간 행의 마지막 픽셀
        pdata_out1 = cache3[DATA_WIDTH-1:0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = cache1[DATA_WIDTH-1:0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && ColsCounterOut == 9'h000) begin
        // 마지막 행의 첫 번째 픽셀
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && 
               ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        // 마지막 행의 중간 픽셀
        pdata_out1 = cache3[DATA_WIDTH-1:0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && ColsCounterOut == 9'h13F) begin
        // 마지막 행의 마지막 픽셀
        pdata_out1 = cache3[DATA_WIDTH-1:0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[DATA_WIDTH-1:0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
    end
  end

endmodule