// 동기화 관련 모듈들을 하나의 파일로 통합

// SyncSignalsDelayer 모듈
module SyncSignalsDelayer #(
  parameter ROW_BITS = 8
)(
  input wire clk,
  input wire fsync_in,
  input wire rsync_in,
  output wire fsync_out,
  output wire rsync_out
);
  
  wire [ROW_BITS-1:0] rowsDelayCounterRising;
  reg [ROW_BITS-1:0] rowsDelayCounterFalling = {ROW_BITS{1'b0}};
  reg rsync2, rsync1, fsync_temp;

  // Counter 인스턴스 생성
  Counter #(.n(ROW_BITS)) RowsCounterComp (
    .clk(rsync2),
    .en(fsync_in),
    .reset(fsync_in),
    .output_count(rowsDelayCounterRising)
  );
  
  assign rsync_out = rsync2;
  assign fsync_out = fsync_temp;
  
  // Step 1 - 두 클럭 사이클 지연
  always @(posedge clk) begin
    rsync2 <= rsync1;
    rsync1 <= rsync_in;
  end

  // Steps 3과 5
  always @(*) begin
    if (rowsDelayCounterRising == 8'h02) begin
      fsync_temp = 1'b1;
    end
    else if (rowsDelayCounterFalling == 8'h00) begin
      fsync_temp = 1'b0;
    end
  end

  // Step 4
  always @(negedge rsync2) begin
    if (fsync_temp == 1'b1) begin
      if (rowsDelayCounterFalling < 8'hEF) begin  // 239
        rowsDelayCounterFalling <= rowsDelayCounterFalling + 1;
      end
      else begin
        rowsDelayCounterFalling <= 8'h00;
      end
    end
    else begin
      rowsDelayCounterFalling <= 8'h00;
    end
  end

endmodule
