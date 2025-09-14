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

    reg signed [10:0] summax, summay;
    reg signed [10:0] summa1, summa2;
    reg signed [10:0] summa;

    always @(posedge pclk_i) begin
        rsync_o <= rsync_i;
        fsync_o <= fsync_i;

        if (fsync_i == 1'b1) begin
            if (rsync_i == 1'b1) begin
                // Sobel edge detection calculation
                // Horizontal gradient (summax)
                // summax = pData3 + 2*pData6 + pData9 - pData1 - 2*pData4 - pData7
                // Vertical gradient (summay)
                // summay = pData7 + 2*pData8 + pData9 - pData1 - 2*pData2 - pData3

                // Calculate horizontal gradient
                summax = $signed({3'b000, pData3}) +
                        $signed({2'b00, pData6, 1'b0}) +
                        $signed({3'b000, pData9}) -
                        $signed({3'b000, pData1}) -
                        $signed({2'b00, pData4, 1'b0}) -
                        $signed({3'b000, pData7});

                // Calculate vertical gradient
                summay = $signed({3'b000, pData7}) +
                        $signed({2'b00, pData8, 1'b0}) +
                        $signed({3'b000, pData9}) -
                        $signed({3'b000, pData1}) -
                        $signed({2'b00, pData2, 1'b0}) -
                        $signed({3'b000, pData3});

                // Absolute value calculation for horizontal gradient
                if (summax[10] == 1'b1) begin
                    summa1 = ~summax + 1;
                end else begin
                    summa1 = summax;
                end

                // Absolute value calculation for vertical gradient
                if (summay[10] == 1'b1) begin
                    summa2 = ~summay + 1;
                end else begin
                    summa2 = summay;
                end

                summa = summa1 + summa2;

                // Threshold = 127
                if (summa > 11'd127) begin
                    pdata_o <= {DATA_WIDTH{1'b1}}; // White
                end else begin
                    pdata_o <= summa[DATA_WIDTH-1:0];
                end
            end
        end
    end

endmodule
