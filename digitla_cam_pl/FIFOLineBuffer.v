// FIFO 라인 버퍼 모듈
module FIFOLineBuffer #(
  parameter DATA_WIDTH = 8,
  parameter NO_OF_COLS = 320
)(
  input wire clk,
  input wire fsync,
  input wire rsync,
  input wire rst_n,          // 활성화 낮음 리셋 추가
  input wire [DATA_WIDTH-1:0] pdata_in,
  output wire [DATA_WIDTH-1:0] pdata_out
);

  // 내부 RAM 배열
  reg [DATA_WIDTH-1:0] ram_array [NO_OF_COLS-1:0];
  wire clk2;
  reg [$clog2(NO_OF_COLS)-1:0] ColsCounter;
  reg [DATA_WIDTH-1:0] pdata_out_reg;
  
  // 클록 반전
  assign clk2 = ~clk;
  assign pdata_out = pdata_out_reg;
  
  // 메모리에서 읽기
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // 리셋 시 출력 레지스터 초기화
      pdata_out_reg <= {DATA_WIDTH{1'b0}};
    end else if (fsync) begin
      if (rsync) begin
        pdata_out_reg <= ram_array[ColsCounter];
      end
    end
  end
  
  // 메모리에 쓰기
  always @(posedge clk2 or negedge rst_n) begin
    if (!rst_n) begin
      // 리셋 시 카운터 초기화
      ColsCounter <= 0;
    end else if (fsync) begin
      if (rsync) begin
        ram_array[ColsCounter] <= pdata_in;
        if (ColsCounter < 319)
          ColsCounter <= ColsCounter + 1'b1;
        else
          ColsCounter <= 0;
      end else begin
        ColsCounter <= 0;
      end
    end
  end

endmodule