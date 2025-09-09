// VHDL 소스 파일: ed_fifo_linebuffer.vhd
// 한 라인의 픽셀 데이터를 저장하는 FIFO 라인 버퍼

module FIFOLineBuffer #(
    parameter DATA_WIDTH = 8,
    parameter NO_OF_COLS = 320
) (
    input wire                  clk,
    input wire                  fsync,
    input wire                  rsync,
    input wire [DATA_WIDTH-1:0] pdata_in,
    output reg [DATA_WIDTH-1:0] pdata_out
);

    // 라인 버퍼로 사용할 RAM 배열 선언
    reg [DATA_WIDTH-1:0] ram_array [0:NO_OF_COLS-1];
    
    // 열 카운터 (주소로 사용)
    reg [$clog2(NO_OF_COLS)-1:0] ColsCounter = 0;

    // RAM에서 데이터 읽기 (상승 에지)
    always @(posedge clk) begin
        if (fsync && rsync) begin
            pdata_out <= ram_array[ColsCounter];
        end
    end

    // RAM에 데이터 쓰기 및 카운터 증가 (하강 에지)
    always @(negedge clk) begin
        if (fsync) begin
            if (rsync) begin
                ram_array[ColsCounter] <= pdata_in;
                if (ColsCounter < NO_OF_COLS - 1) begin
                    ColsCounter <= ColsCounter + 1;
                end else begin
                    ColsCounter <= 0;
                end
            end else begin
                ColsCounter <= 0;
            end
        end
    end

endmodule
