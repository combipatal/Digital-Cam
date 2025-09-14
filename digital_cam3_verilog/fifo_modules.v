// FIFO 관련 모듈들을 하나의 파일로 통합

// SMALL_INTEGER 타입을 상수로 정의
// Verilog에서는 별도의 타입 정의가 없으므로 로직에 직접 반영됨

// FIFOLineBuffer 모듈
module FIFOLineBuffer #(
  parameter DATA_WIDTH = 8,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
  input wire fsync,
  input wire rsync,
  input wire [DATA_WIDTH-1:0] pdata_in,
  output reg [DATA_WIDTH-1:0] pdata_out
);

  // RAM 정의
  reg [DATA_WIDTH-1:0] ram_array [0:NO_OF_COLS-1];
  wire clk2;
  reg [8:0] ColsCounter = 0;  // 0-319까지 사용하므로 9비트 필요

  // 클럭 반전
  assign clk2 = ~clk;

  // 메모리에서 읽기
  always @(posedge clk) begin
    if (fsync && rsync) begin
      pdata_out <= ram_array[ColsCounter];
    end
  end

  // 메모리에 쓰기
  always @(posedge clk2) begin
    if (fsync) begin
      if (rsync) begin
        ram_array[ColsCounter] <= pdata_in;
        if (ColsCounter < 319) begin
          ColsCounter <= ColsCounter + 1;
        end else begin
          ColsCounter <= 0;
        end
      end else begin
        ColsCounter <= 0;
      end
    end
  end
endmodule

// DoubleFIFOLineBuffer 모듈
module DoubleFiFOLineBuffer #(
  parameter DATA_WIDTH = 8,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
  input wire fsync,
  input wire rsync,
  input wire [DATA_WIDTH-1:0] pdata_in,
  output wire [DATA_WIDTH-1:0] pdata_out1,
  output wire [DATA_WIDTH-1:0] pdata_out2,
  output wire [DATA_WIDTH-1:0] pdata_out3
);

  // 내부 신호
  wire [DATA_WIDTH-1:0] internal_pdata_out2;
  wire [DATA_WIDTH-1:0] internal_pdata_out3;

  // 라인 버퍼 인스턴스
  FIFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) LineBuffer1 (
    .clk(clk),
    .fsync(fsync),
    .rsync(rsync),
    .pdata_in(pdata_in),
    .pdata_out(internal_pdata_out2)
  );

  FIFOLineBuffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NO_OF_COLS(NO_OF_COLS)
  ) LineBuffer2 (
    .clk(clk),
    .fsync(fsync),
    .rsync(rsync),
    .pdata_in(internal_pdata_out2),
    .pdata_out(internal_pdata_out3)
  );

  // 출력 할당
  assign pdata_out1 = pdata_in;
  assign pdata_out2 = internal_pdata_out2;
  assign pdata_out3 = internal_pdata_out3;

endmodule
