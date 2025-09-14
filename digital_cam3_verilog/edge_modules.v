// 엣지 검출 관련 모듈들을 하나의 파일로 통합

// Sobel 엣지 검출 커널
module edge_sobel #(
  parameter DATA_WIDTH = 8
)(
  input wire pclk_i,
  input wire fsync_i,
  input wire rsync_i,
  input wire [DATA_WIDTH-1:0] pData1,
  input wire [DATA_WIDTH-1:0] pData2,
  input wire [DATA_WIDTH-1:0] pData3,
  input wire [DATA_WIDTH-1:0] pData4,
  input wire [DATA_WIDTH-1:0] pData5,
  input wire [DATA_WIDTH-1:0] pData6,
  input wire [DATA_WIDTH-1:0] pData7,
  input wire [DATA_WIDTH-1:0] pData8,
  input wire [DATA_WIDTH-1:0] pData9,
  output reg fsync_o,
  output reg rsync_o,
  output reg [DATA_WIDTH-1:0] pdata_o
);

  reg [10:0] summax, summay, summa1, summa2, summa;

  always @(posedge pclk_i) begin
    rsync_o <= rsync_i;
    fsync_o <= fsync_i;
    
    if (fsync_i == 1'b1) begin
      if (rsync_i == 1'b1) begin
        // X 방향 Sobel 필터 적용
        summax = 
          ({3'b000, pData3} + {2'b00, pData6, 1'b0} + {3'b000, pData9}) -
          ({3'b000, pData1} + {2'b00, pData4, 1'b0} + {3'b000, pData7});
        
        // Y 방향 Sobel 필터 적용
        summay = 
          ({3'b000, pData7} + {2'b00, pData8, 1'b0} + {3'b000, pData9}) -
          ({3'b000, pData1} + {2'b00, pData2, 1'b0} + {3'b000, pData3});
        
        // 절대값 계산
        if (summax[10] == 1'b1) begin
          summa1 = ~summax + 1;
        end else begin
          summa1 = summax;
        end
        
        if (summay[10] == 1'b1) begin
          summa2 = ~summay + 1;
        end else begin
          summa2 = summay;
        end
        
        summa = summa1 + summa2;
        
        // 임계값 적용 (127)
        if (summa > 11'b00001111111) begin
          pdata_o <= {DATA_WIDTH{1'b1}}; // 흰색
        end else begin
          pdata_o <= summa[DATA_WIDTH-1:0];
        end
      end
    end
  end

endmodule

// Sobel 엣지 검출 래퍼
module edge_sobel_wrapper #(
  parameter DATA_WIDTH = 8
)(
  input wire clk,
  input wire fsync_in,
  input wire rsync_in,
  input wire [DATA_WIDTH-1:0] pdata_in,
  output wire fsync_out,
  output wire rsync_out,
  output wire [DATA_WIDTH-1:0] pdata_out
);

  // 내부 신호 선언
  wire [DATA_WIDTH-1:0] pdata_int1;
  wire [DATA_WIDTH-1:0] pdata_int2;
  wire [DATA_WIDTH-1:0] pdata_int3;
  wire [DATA_WIDTH-1:0] pdata_int4;
  wire [DATA_WIDTH-1:0] pdata_int5;
  wire [DATA_WIDTH-1:0] pdata_int6;
  wire [DATA_WIDTH-1:0] pdata_int7;
  wire [DATA_WIDTH-1:0] pdata_int8;
  wire [DATA_WIDTH-1:0] pdata_int9;
  wire fsynch_int;
  wire rsynch_int;

  // CacheSystem 인스턴스
  CacheSystem #(
    .DATA_WIDTH(DATA_WIDTH),
    .WINDOW_SIZE(3),
    .ROW_BITS(8),
    .COL_BITS(9),
    .NO_OF_ROWS(240),
    .NO_OF_COLS(320)
  ) CacheSystem_inst (
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

  // edge_sobel 인스턴스
  edge_sobel #(
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
