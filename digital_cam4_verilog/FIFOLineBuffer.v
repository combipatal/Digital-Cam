// VHDL 소스 파일: ed_fifo_linebuffer.vhd
// 한 라인의 픽셀 데이터를 저장하는 FIFO 라인 버퍼
// [수정됨] 안정적인 단일 클럭 엣지 설계로 전면 재작성

module FIFOLineBuffer #(
    parameter DATA_WIDTH = 8,
    parameter NO_OF_COLS = 320
) (
    input wire                  clk,
    input wire                  fsync,      // Frame sync (전체 프레임의 유효 구간)
    input wire                  rsync,      // Row sync (한 줄의 유효 구간, enable 역할)
    input wire [DATA_WIDTH-1:0] pdata_in,
    output reg [DATA_WIDTH-1:0] pdata_out   // 한 라인 지연된 데이터 출력
);

    // 라인 버퍼로 사용할 Block RAM 배열 선언
    reg [DATA_WIDTH-1:0] ram_array [0:NO_OF_COLS-1];
    
    // 열 카운터 (RAM의 주소로 사용)
    reg [$clog2(NO_OF_COLS)-1:0] col_cntr = 0;

    // 모든 동작은 clk의 상승 엣지에서만 동기적으로 일어납니다.
    always @(posedge clk) begin
        // 유효한 한 줄의 데이터가 들어오고 있을 때 (rsync가 활성화되었을 때)
        if (rsync) begin
            // 1. 현재 주소(col_cntr)에 새 픽셀 데이터를 씁니다.
            ram_array[col_cntr] <= pdata_in;
            
            // 2. 동시에 현재 주소(col_cntr)에서 이전 라인의 픽셀 데이터를 읽어옵니다.
            //    FPGA의 Block RAM은 이런 동작을 한 클럭에 안정적으로 처리할 수 있습니다.
            //    읽어온 값은 다음 사이클 출력을 위해 pdata_out 레지스터에 저장됩니다.
            pdata_out <= ram_array[col_cntr];
        end
        
        // 카운터 로직
        // 프레임이 유효하지 않으면 카운터를 리셋합니다.
        if (!fsync) begin
            col_cntr <= 0;
        // 유효한 줄 데이터가 들어올 때만 카운터를 증가시킵니다.
        end else if (rsync) begin
            if (col_cntr == NO_OF_COLS - 1) begin
                col_cntr <= 0; // 줄의 끝에 도달하면 0으로 돌아갑니다.
            end else begin
                col_cntr <= col_cntr + 1;
            end
        end
    end

endmodule