module debounce #(
    parameter WIDTH = 1,          // 디바운싱할 버튼의 수
    parameter POLARITY = 1,       // 1: Active High, 0: Active Low
    parameter COUNTER_BITS = 16,  // 디바운싱 카운터 비트 수
    parameter COUNTER_MAX = 50000 // 약 1ms @ 50MHz
)(
    input wire clk,               // 시스템 클럭
    input wire [WIDTH-1:0] button_in, // 불안정한 버튼 입력
    output reg [WIDTH-1:0] button_pulse // 1클럭 동안 유지되는 안정화된 출력 펄스
);

    reg [WIDTH-1:0] sync_reg1;
    reg [WIDTH-1:0] sync_reg2;
    reg [WIDTH-1:0] debounced_state;
    reg [WIDTH-1:0] prev_debounced_state;
    reg [COUNTER_BITS-1:0] counter [WIDTH-1:0];
    integer i;

    initial begin
        for (i = 0; i < WIDTH; i = i + 1) begin
            debounced_state[i] = ~POLARITY;
            prev_debounced_state[i] = ~POLARITY;
        end
    end

    always @(posedge clk) begin
        sync_reg1 <= button_in;
        sync_reg2 <= sync_reg1;

        for (i = 0; i < WIDTH; i = i + 1) begin
            prev_debounced_state[i] <= debounced_state[i];

            if (sync_reg2[i] != debounced_state[i]) begin
                counter[i] <= 0;
            end else if (counter[i] < COUNTER_MAX) begin
                counter[i] <= counter[i] + 1;
            end else begin
                debounced_state[i] <= sync_reg2[i];
            end
        end
    end

    always @(posedge clk) begin
        for (i = 0; i < WIDTH; i = i + 1) begin
            if (debounced_state[i] == (POLARITY ? 1'b1 : 1'b0) && prev_debounced_state[i] == (POLARITY ? 1'b0 : 1'b1)) begin
                button_pulse[i] <= 1'b1;
            end else begin
                button_pulse[i] <= 1'b0;
            end
        end
    end

endmodule
