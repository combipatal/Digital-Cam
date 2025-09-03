// ============================================
// Clock Divider Module (50MHz → 25MHz)
// 단순히 클럭 토글을 반 주기로 바꿔서 나눔
// ============================================
module clk_divider (
    input wire clk_in,     // 50MHz 입력
    input wire reset_n,    // 리셋 (low일 때 초기화)
    output reg clk_out     // 25MHz 출력
);
    always @(posedge clk_in or negedge reset_n) begin
        if (!reset_n)
            clk_out <= 1'b0;     // 리셋 시 0으로 초기화
        else
            clk_out <= ~clk_out; // 클럭 토글
    end
endmodule