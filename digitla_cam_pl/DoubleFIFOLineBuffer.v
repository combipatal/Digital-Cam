// 이중 FIFO 라인 버퍼 모듈
module DoubleFIFOLineBuffer #(
  parameter DATA_WIDTH = 8,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
  input wire rst_n,          // 활성화 낮음 리셋
  input wire fsync,
  input wire rsync,
  input wire [DATA_WIDTH-1:0] pdata_in,
  output wire [DATA_WIDTH-1:0] pdata_out1,
  output wire [DATA_WIDTH-1:0] pdata_out2,
  output wire [DATA_WIDTH-1:0] pdata_out3
);

  // 첫번째 라인 버퍼
  FIFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) LineBuffer1 (
    .clk(clk),
    .fsync(fsync),
    .rsync(rsync),
    .pdata_in(pdata_in),
    .pdata_out(pdata_out2),
    .rst_n(rst_n)
  );
  
  // 두번째 라인 버퍼
  FIFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) LineBuffer2 (
    .clk(clk),
    .fsync(fsync),
    .rsync(rsync),
    .pdata_in(pdata_out2),
    .pdata_out(pdata_out3),
    .rst_n(rst_n)
  );
  
  // 입력 직접 출력
  assign pdata_out1 = pdata_in;

endmodule