module Counter #(parameter n = 9)(
    input clk,
    input en,      // enable
    input reset,   // Active Low
    output [n-1:0] output_count
);

    reg [n-1:0] num;

    always @(posedge clk, negedge reset) begin
        if (reset == 1'b0) begin
            num <= {n{1'b0}};
        end else begin
            if (en == 1'b1) begin
                num <= num + 1;
            end
        end
    end

    assign output_count = num;

endmodule
