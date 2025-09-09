// VHDL 소스 파일: ed_sobel_kernel.vhd
// 3x3 Sobel 에지 검출 커널

module edge_sobel #(
    parameter DATA_WIDTH = 8
) (
    input wire                      pclk_i,
    input wire                      fsync_i,
    input wire                      rsync_i,
    input wire [DATA_WIDTH-1:0]     pData1,
    input wire [DATA_WIDTH-1:0]     pData2,
    input wire [DATA_WIDTH-1:0]     pData3,
    input wire [DATA_WIDTH-1:0]     pData4,
    input wire [DATA_WIDTH-1:0]     pData5,
    input wire [DATA_WIDTH-1:0]     pData6,
    input wire [DATA_WIDTH-1:0]     pData7,
    input wire [DATA_WIDTH-1:0]     pData8,
    input wire [DATA_WIDTH-1:0]     pData9,
    output reg                      fsync_o,
    output reg                      rsync_o,
    output reg [DATA_WIDTH-1:0]     pdata_o
);

    reg signed [10:0] summax, summay;
    reg [10:0] summa1, summa2, summa;
    
    // Sobel 연산을 위한 3x3 픽셀 값
    wire signed [10:0] p1, p2, p3, p4, p6, p7, p8, p9;
    
    // 입력 픽셀 값을 부호 있는 11비트로 확장
    assign p1 = {{3{1'b0}}, pData1};
    assign p2 = {{3{1'b0}}, pData2};
    assign p3 = {{3{1'b0}}, pData3};
    assign p4 = {{3{1'b0}}, pData4};
    // p5는 연산에 사용되지 않음
    assign p6 = {{3{1'b0}}, pData6};
    assign p7 = {{3{1'b0}}, pData7};
    assign p8 = {{3{1'b0}}, pData8};
    assign p9 = {{3{1'b0}}, pData9};
    

    always @(posedge pclk_i) begin
        // 동기화 신호 지연 출력
        rsync_o <= rsync_i;
        fsync_o <= fsync_i;
        
        if (fsync_i) begin
            if (rsync_i) begin
                // Gx = (P3 + 2*P6 + P9) - (P1 + 2*P4 + P7)
                summax <= (p3 + (p6 << 1) + p9) - (p1 + (p4 << 1) + p7);
                
                // Gy = (P7 + 2*P8 + P9) - (P1 + 2*P2 + P3)
                summay <= (p7 + (p8 << 1) + p9) - (p1 + (p2 << 1) + p3);

                // 절대값 계산: |Gx|
                if (summax[10]) begin
                    summa1 <= ~summax + 1; // 2's complement
                end else begin
                    summa1 <= summax;
                end
                
                // 절대값 계산: |Gy|
                if (summay[10]) begin
                    summa2 <= ~summay + 1; // 2's complement
                end else begin
                    summa2 <= summay;
                end
                
                // 에지 강도 근사 계산: |Gx| + |Gy|
                summa <= summa1 + summa2;
                
                // 임계값(Threshold) 처리 (127)
                if (summa > 11'd127) begin
                    pdata_o <= {DATA_WIDTH{1'b1}}; // White
                end else begin
                    pdata_o <= summa[DATA_WIDTH-1:0];
                end
            end
        end
    end

endmodule
