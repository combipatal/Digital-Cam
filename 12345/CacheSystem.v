module CacheSystem #(
  parameter DATA_WIDTH = 8,
  parameter WINDOW_SIZE = 3,
  parameter ROW_BITS = 8,   // 640x480의 경우 9
  parameter COL_BITS = 9,   // 640x480의 경우 10
  parameter NO_OF_ROWS = 240,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
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

  // 내부 신호 선언
  wire [ROW_BITS-1:0] RowsCounterOut;
  wire [COL_BITS-1:0] ColsCounterOut;
  wire [DATA_WIDTH-1:0] dout1;
  wire [DATA_WIDTH-1:0] dout2;
  wire [DATA_WIDTH-1:0] dout3;
  wire fsync_temp, rsync_temp;
  
  // 픽셀 요소 캐시
  // |--------------------------------|
  // | z9-z6-z3 | z8-z5-z2 | z7-z4-z1 |
  // |--------------------------------|
  // 23       16|15       8|7         0
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache1;
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache2;
  reg [(WINDOW_SIZE*DATA_WIDTH)-1:0] cache3;

  // DoubleFIFOLineBuffer 인스턴스
  DoubleFiFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) DoubleLineBuffer (
    .clk(clk),
    .fsync(fsync_in),
    .rsync(rsync_in),
    .pdata_in(pdata_in),
    .pdata_out1(dout1),
    .pdata_out2(dout2),
    .pdata_out3(dout3)
  );

  // SyncSignalsDelayer 인스턴스
  SyncSignalsDelayer #(
    .ROW_BITS(ROW_BITS)
  ) Delayer (
    .clk(clk),
    .fsync_in(fsync_in),
    .rsync_in(rsync_in),
    .fsync_out(fsync_temp),
    .rsync_out(rsync_temp)
  );

  // 카운터 인스턴스
  Counter #(.n(8)) RowsCounter (
    .clk(rsync_temp),
    .en(fsync_temp),
    .reset(fsync_temp),
    .output_count(RowsCounterOut)
  );

  Counter #(.n(9)) ColsCounter (
    .clk(clk),
    .en(rsync_temp),
    .reset(rsync_temp),
    .output_count(ColsCounterOut)
  );

  // 출력 할당
  assign fsync_out = fsync_temp;
  assign rsync_out = rsync_temp;

  // Shifting 프로세스
  always @(posedge clk) begin
    // 중간 부분의 픽셀이 하위 부분으로 복사됨
    cache1[DATA_WIDTH-1:0] <= cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
    cache2[DATA_WIDTH-1:0] <= cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
    cache3[DATA_WIDTH-1:0] <= cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
    
    // 상위 부분의 픽셀이 중간 부분으로 복사됨
    cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
    cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
    cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)] <= cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
    
    // RAM의 출력이 상위 부분에 들어감
    cache1[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout1;
    cache2[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout2;
    cache3[(WINDOW_SIZE*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)] <= dout3;
  end

  // Emitting 프로세스
  always @(*) begin
    if (fsync_temp == 1'b1) begin
      if (RowsCounterOut == 8'h00 && ColsCounterOut == 9'h000) begin
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):((WINDOW_SIZE-2)*DATA_WIDTH)];
        pdata_out9 = cache1[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut == 8'h00 && ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = cache1[(DATA_WIDTH-1):0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut == 8'h00 && ColsCounterOut == 9'h13F) begin
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = {DATA_WIDTH{1'b0}};
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = cache1[(DATA_WIDTH-1):0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && ColsCounterOut == 9'h000) begin
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        pdata_out1 = cache3[(DATA_WIDTH-1):0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = cache1[(DATA_WIDTH-1):0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = cache1[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
      end
      else if (RowsCounterOut > 8'h00 && RowsCounterOut < 8'hEF && ColsCounterOut == 9'h13F) begin
        pdata_out1 = cache3[(DATA_WIDTH-1):0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = cache1[(DATA_WIDTH-1):0];
        pdata_out8 = cache1[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && ColsCounterOut == 9'h000) begin
        pdata_out1 = {DATA_WIDTH{1'b0}};
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = {DATA_WIDTH{1'b0}};
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && ColsCounterOut > 9'h000 && ColsCounterOut < 9'h13F) begin
        pdata_out1 = cache3[(DATA_WIDTH-1):0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = cache3[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = cache2[((WINDOW_SIZE)*DATA_WIDTH-1):((WINDOW_SIZE-1)*DATA_WIDTH)];
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
      else if (RowsCounterOut == 8'hEF && ColsCounterOut == 9'h13F) begin
        pdata_out1 = cache3[(DATA_WIDTH-1):0];
        pdata_out2 = cache3[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out3 = {DATA_WIDTH{1'b0}};
        pdata_out4 = cache2[(DATA_WIDTH-1):0];
        pdata_out5 = cache2[((WINDOW_SIZE-1)*DATA_WIDTH-1):DATA_WIDTH];
        pdata_out6 = {DATA_WIDTH{1'b0}};
        pdata_out7 = {DATA_WIDTH{1'b0}};
        pdata_out8 = {DATA_WIDTH{1'b0}};
        pdata_out9 = {DATA_WIDTH{1'b0}};
      end
    end
  end

endmodule
