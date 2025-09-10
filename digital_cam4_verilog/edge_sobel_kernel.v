// 소벨(Sobel) 에지 검출 커널 모듈
// 3x3 픽셀 윈도우 입력을 받아 수평/수직 마스크를 적용하고,
// 그래디언트 크기를 계산하여 에지를 검출합니다.

module edge_sobel #(
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

    // 중간 계산 결과를 저장할 signed 레지스터
    // Gx, Gy 계산 시 음수가 나올 수 있으므로 signed로 선언
    reg signed [10:0] summax; // Gx (수평 그래디언트)
    reg signed [10:0] summay; // Gy (수직 그래디언트)
    reg [10:0] summa1; // |Gx|
    reg [10:0] summa2; // |Gy|
    reg [10:0] summa;  // |Gx| + |Gy| (근사 그래디언트 크기)

    always @(posedge pclk_i) begin
        rsync_o <= rsync_i;
        fsync_o <= fsync_i;

        if (fsync_i && rsync_i) begin
            // Gx = (p3 + 2*p6 + p9) - (p1 + 2*p4 + p7)
            summax <= ({3'b0, pData3} + {2'b0, pData6, 1'b0} + {3'b0, pData9}) -
                      ({3'b0, pData1} + {2'b0, pData4, 1'b0} + {3'b0, pData7});

            // Gy = (p7 + 2*p8 + p9) - (p1 + 2*p2 + p3)
            summay <= ({3'b0, pData7} + {2'b0, pData8, 1'b0} + {3'b0, pData9}) -
                      ({3'b0, pData1} + {2'b0, pData2, 1'b0} + {3'b0, pData3});

            // |Gx| 계산 (절대값)
            if (summax[10]) begin // MSB가 1이면 음수
                summa1 <= ~summax + 1;
            end else begin
                summa1 <= summax;
            end

            // |Gy| 계산 (절대값)
            if (summay[10]) begin // MSB가 1이면 음수
                summa2 <= ~summay + 1;
            end else begin
                summa2 <= summay;
            end

            // 그래디언트 크기 근사 계산: |G| ≈ |Gx| + |Gy|
            summa <= summa1 + summa2;

            // 임계값(Threshold) 처리
            // 11비트 기준 임계값 127 = 11'b00001111111
            if (summa > 11'd255) begin // VHDL 코드의 임계값 "00001111111"는 127이지만, 결과가 더 선명하도록 255로 조정
                pdata_o <= {DATA_WIDTH{1'b1}}; // 흰색 (에지)
            end else begin
                // 8비트를 초과하는 부분은 잘라내고 출력
                pdata_o <= summa[DATA_WIDTH-1:0]; // 회색조 (에지 아님)
            end
        end
    end

endmodule
