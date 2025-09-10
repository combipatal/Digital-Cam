// 소벨 에지 검출 커널 (4-Stage Pipelined Version)
// 133MHz와 같은 고속 클럭에서 안정적으로 동작하도록 파이프라인 구조를 적용했습니다.
// 연산 과정을 4단계로 분리하여 각 단계의 조합 논리 경로를 줄였습니다.
// 이로 인해 4 클럭의 지연(latency)이 발생하며, 동기화 신호(fsync, rsync)도 함께 지연시켜 출력합니다.

module edge_sobel_pipelined #(
    parameter DATA_WIDTH = 8
)(
    input pclk_i,
    input fsync_i,
    input rsync_i,
    input [DATA_WIDTH-1:0] pData1, input [DATA_WIDTH-1:0] pData2, input [DATA_WIDTH-1:0] pData3,
    input [DATA_WIDTH-1:0] pData4, input [DATA_WIDTH-1:0] pData5, input [DATA_WIDTH-1:0] pData6,
    input [DATA_WIDTH-1:0] pData7, input [DATA_WIDTH-1:0] pData8, input [DATA_WIDTH-1:0] pData9,
    output reg fsync_o,
    output reg rsync_o,
    output reg [DATA_WIDTH-1:0] pdata_o
);

    // --- 파이프라인 단계별 레지스터 ---

    // Stage 1 -> 2: Gx, Gy 계산 결과 저장
    reg signed [10:0] summax_s1, summay_s1;

    // Stage 2 -> 3: |Gx|, |Gy| (절대값) 계산 결과 저장
    reg [10:0] summa1_s2, summa2_s2;

    // Stage 3 -> 4: 최종 출력 픽셀 값 저장
    reg [DATA_WIDTH-1:0] pdata_out_s3;
    
    // 동기화 신호를 데이터 파이프라인 지연(4 클럭)에 맞추기 위한 딜레이 레지스터
    reg [3:0] fsync_delay, rsync_delay;
	 reg [10:0] summa_temp;
    always @(posedge pclk_i) begin
        // --- 파이프라인 Stage 1: Gx, Gy 계산 ---
        // 9개의 입력 픽셀(pData1~9)을 사용하여 Gx와 Gy를 계산하고 결과를 레지스터(summax_s1, summay_s1)에 저장합니다.
        summax_s1 <= ({3'b0, pData3} + ({2'b0, pData6, 1'b0}) + {3'b0, pData9}) -
                     ({3'b0, pData1} + ({2'b0, pData4, 1'b0}) + {3'b0, pData7});

        summay_s1 <= ({3'b0, pData7} + ({2'b0, pData8, 1'b0}) + {3'b0, pData9}) -
                     ({3'b0, pData1} + ({2'b0, pData2, 1'b0}) + {3'b0, pData3});

        // --- 파이프라인 Stage 2: 절대값 계산 ---
        // 이전 단계에서 저장된 Gx, Gy 값을 사용하여 절대값을 계산하고 레지스터(summa1_s2, summa2_s2)에 저장합니다.
        if (summax_s1[10]) summa1_s2 <= ~summax_s1 + 1;
        else              summa1_s2 <= summax_s1;

        if (summay_s1[10]) summa2_s2 <= ~summay_s1 + 1;
        else              summa2_s2 <= summay_s1;

        // --- 파이프라인 Stage 3: 합산 및 임계값 처리 ---
        // 이전 단계의 절대값들을 더하고, 임계값과 비교하여 최종 픽셀 값을 결정한 후 레지스터(pdata_out_s3)에 저장합니다.

        summa_temp = summa1_s2 + summa2_s2;
        
        if (summa_temp > 11'd255) // 임계값 255
            pdata_out_s3 <= {DATA_WIDTH{1'b1}}; // White (Edge)
        else
            pdata_out_s3 <= summa_temp[DATA_WIDTH-1:0]; // Grayscale (Not Edge)

        // --- 파이프라인 Stage 4: 최종 출력 ---
        // 최종 처리된 픽셀 값을 출력 레지스터(pdata_o)로 전달합니다.
        pdata_o <= pdata_out_s3;

        // --- 동기화 신호 지연 파이프라인 ---
        // fsync와 rsync 신호를 4클럭만큼 지연시켜 데이터 출력과 타이밍을 맞춥니다.
        fsync_delay <= {fsync_delay[2:0], fsync_i};
        rsync_delay <= {rsync_delay[2:0], rsync_i};

        fsync_o <= fsync_delay[3];
        rsync_o <= rsync_delay[3];
    end

endmodule
