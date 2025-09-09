// VHDL 소스 파일: ed_counter.vhd
// N-bit Generic Counter

module Counter #(
    parameter n = 9
) (
    input wire          clk,
    input wire          en,
    input wire          reset,  // Active Low
    output wire [n-1:0] output_val
);

    reg [n-1:0] num;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            num <= 0;
        end else begin
            if (en) begin
                num <= num + 1;
            end
        end
    end

    assign output_val = num;

endmodule
