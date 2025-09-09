// VHDL 소스 파일: ed_sync_signals_delayer.vhd
// Sobel 필터의 파이프라인 지연을 보상하기 위해 동기화 신호를 지연시킵니다.
// rsync (hsync)는 2 클럭, fsync (vsync)는 (라인 너비 + 2) 픽셀만큼 지연됩니다.

module SyncSignalsDelayer #(
    parameter ROW_BITS = 8,
    parameter NO_OF_ROWS = 240
) (
    input wire  clk,
    input wire  fsync_in,
    input wire  rsync_in,
    output wire fsync_out,
    output wire rsync_out
);

    reg [ROW_BITS-1:0] rowsDelayCounterRising;
    reg [ROW_BITS-1:0] rowsDelayCounterFalling;

    reg rsync1, rsync2;
    reg fsync_temp;

    assign rsync_out = rsync2;
    assign fsync_out = fsync_temp;

    // rsync_in을 2 클럭 지연시켜 rsync2 생성 (2단 시프트 레지스터)
    always @(posedge clk) begin
        rsync1 <= rsync_in;
        rsync2 <= rsync1;
    end
    
    // rowsDelayCounterRising: rsync2의 상승 에지에서 카운트
    // fsync_in이 활성화된 동안 라인 수를 셉니다.
    always @(posedge rsync2 or negedge fsync_in) begin
        if (!fsync_in) begin
            rowsDelayCounterRising <= 0;
        end else begin
            rowsDelayCounterRising <= rowsDelayCounterRising + 1;
        end
    end

    // fsync_out 신호 생성 로직 (SR 래치와 유사하게 동작)
    // rowsDelayCounterRising이 2가 되면 Set (fsync_temp = 1)
    // rowsDelayCounterFalling이 0이 되면 Reset (fsync_temp = 0)
    always @(*) begin
        if (rowsDelayCounterRising == 2) begin
            fsync_temp = 1'b1;
        end else if (rowsDelayCounterFalling == 0) begin
            fsync_temp = 1'b0;
        end else begin
            // 의도하지 않은 래치(latch) 생성을 방지하기 위해 현재 상태 유지
            fsync_temp = fsync_temp; 
        end
    end
    
    // rowsDelayCounterFalling: rsync2의 하강 에지에서 카운트
    always @(negedge rsync2) begin
        if (fsync_temp) begin
            if (rowsDelayCounterFalling < NO_OF_ROWS - 1) begin // 239
                rowsDelayCounterFalling <= rowsDelayCounterFalling + 1;
            end else begin
                rowsDelayCounterFalling <= 0;
            end
        end else begin
            rowsDelayCounterFalling <= 0;
        end
    end

endmodule

