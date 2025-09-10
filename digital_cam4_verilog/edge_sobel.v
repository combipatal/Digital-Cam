// 3x3 픽셀 윈도우를 입력받아 소벨 연산을 수행하는 커널 모듈
// Gx, Gy 그래디언트를 계산하고, 절대값의 합을 통해 최종 에지 강도를 출력합니다.

module edge_sobel #(
    parameter DATA_WIDTH = 8
)(
    input pclk_i,
    input fsync_i,
    input rsync_i,
    input [DATA_WIDTH-1:0] pData1,
    input [DATA_WIDTH-1:0] pData2,
    input [DATA_WIDTH-1:0] pData3,
    input [DATA_WIDTH-1:0] pData4,
    input [DATA_WIDTH-1:0] pData5,
    input [DATA_WIDTH-1:0] pData6,
    input [DATA_WIDTH-1:0] pData7,
    input [DATA_WIDTH-1:0] pData8,
    input [DATA_WIDTH-1:0] pData9,
    output reg fsync_o,
    output reg rsync_o,
    output reg [DATA_WIDTH-1:0] pdata_o
);

    // [오류 수정] Verilog에서는 always 블록 밖에서 reg 변수를 선언해야 합니다.
    // 연산 과정에서 부호 비트와 오버플로우를 고려하여 충분한 비트 폭을 할당합니다.
    reg signed [10:0] summax, summay;
    reg signed [10:0] summa1, summa2;
    reg signed [10:0] summa;

    // 임계값 (Threshold)
    localparam THRESHOLD = 11'd127;

    always @(posedge pclk_i) begin
        // 동기화 신호는 그대로 통과시킵니다.
        rsync_o <= rsync_i;
        fsync_o <= fsync_i;

        if (fsync_i && rsync_i) begin
            // Gx = (p3 + 2*p6 + p9) - (p1 + 2*p4 + p7)
            summax =  ({3'b0, pData3} + {2'b0, pData6, 1'b0} + {3'b0, pData9}) -
                      ({3'b0, pData1} + {2'b0, pData4, 1'b0} + {3'b0, pData7});

            // Gy = (p7 + 2*p8 + p9) - (p1 + 2*p2 + p3)
            summay =  ({3'b0, pData7} + {2'b0, pData8, 1'b0} + {3'b0, pData9}) -
                      ({3'b0, pData1} + {2'b0, pData2, 1'b0} + {3'b0, pData3});

            // 절대값 계산 |Gx|
            if (summax[10]) begin // 최상위 비트(부호 비트)가 1이면 음수
                summa1 = -summax;
            end else begin
                summa1 = summax;
            end

            // 절대값 계산 |Gy|
            if (summay[10]) begin // 최상위 비트(부호 비트)가 1이면 음수
                summa2 = -summay;
            end else begin
                summa2 = summay;
            end

            // 에지 강도 근사치 계산 |G| approx |Gx| + |Gy|
            summa = summa1 + summa2;

            // 임계값 비교
            if (summa > THRESHOLD) begin
                pdata_o <= {DATA_WIDTH{1'b1}}; // White (에지로 판단)
            end else begin
                // 결과값이 8비트를 초과할 수 있으므로 상위 비트는 잘라냅니다.
                pdata_o <= summa[DATA_WIDTH-1:0];
            end
        end
    end

endmodule

