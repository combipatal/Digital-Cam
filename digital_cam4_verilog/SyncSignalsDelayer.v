// 동기화 신호 지연기 모듈
// 데이터 파이프라인 지연에 맞춰 vsync와 hsync 신호를 지연시킵니다.
// 소벨 필터 파이프라인이 채워지는 시간(2라인 + 2클럭)을 보상하기 위함입니다.
// 참고: VHDL 원본의 일부 로직(다른 클럭 엣지, 게이트된 클럭 사용)은
// 일반적인 합성에 부적합하여, 동일한 기능을 하도록 단일 클럭 기반으로 수정했습니다.

module SyncSignalsDelayer #(
    parameter ROW_BITS = 8,
    parameter NO_OF_ROWS = 240
)(
    input clk,
    input fsync_in,
    input rsync_in,
    output fsync_out,
    output rsync_out
);

    // rsync_in을 2 클럭 사이클만큼 지연시키기 위한 레지스터
    reg rsync1, rsync2;
    always @(posedge clk) begin
        rsync1 <= rsync_in;
        rsync2 <= rsync1;
    end
    assign rsync_out = rsync2;

    // fsync 지연 로직
    reg fsync_temp = 1'b0;
    assign fsync_out = fsync_temp;

    reg [ROW_BITS-1:0] rowsDelayCounterRising = 0;
    reg [ROW_BITS-1:0] rowsDelayCounterFalling = 0;

    wire rsync2_posedge = rsync1 == 1'b0 && rsync2 == 1'b1; // rsync2의 상승 엣지 검출
    wire rsync2_negedge = rsync1 == 1'b1 && rsync2 == 1'b0; // rsync2의 하강 엣지 검출

    // VHDL의 Step 2 & 3 & 5: fsync_temp 신호 생성
    always @(posedge clk) begin
        // rowsDelayCounterRising: rsync2의 상승 엣지마다 카운트
        if (fsync_in) begin
            if (rsync2_posedge) begin
                rowsDelayCounterRising <= rowsDelayCounterRising + 1;
            end
        end else begin
            rowsDelayCounterRising <= 0;
        end

        // fsync_temp를 1로 설정하는 조건
        if (rowsDelayCounterRising == 2) begin
            fsync_temp <= 1'b1;
        // fsync_temp를 0으로 설정하는 조건
        end else if (rowsDelayCounterFalling == 0 && rsync2_negedge && fsync_temp) begin
             // 프레임의 마지막 라인이 끝나면 fsync_temp를 0으로 만듦
            if(rowsDelayCounterFalling == NO_OF_ROWS-1)
                fsync_temp <= 1'b0;
        end else if (!fsync_in) begin
             fsync_temp <= 1'b0;
        end
    end

    // VHDL의 Step 4: rowsDelayCounterFalling 카운터
    always @(posedge clk) begin
        if(rsync2_negedge) begin // rsync2 하강 엣지에서
            if (fsync_temp) begin
                if (rowsDelayCounterFalling < NO_OF_ROWS - 1) begin
                    rowsDelayCounterFalling <= rowsDelayCounterFalling + 1;
                end else begin
                    rowsDelayCounterFalling <= 0;
                end
            end else begin
                rowsDelayCounterFalling <= 0;
            end
        end
    end

endmodule

