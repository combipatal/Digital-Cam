`timescale 1ns / 1ps

// ===================================================================
// Module: seven_segment_decoder
// Description: 4비트 2진수 입력을 Common Anode 방식의 7세그먼트 출력으로 변환합니다.
//              (0일 때 ON, 1일 때 OFF)
// ===================================================================
module seven_segment_decoder (
    input [3:0] binary_in,      // 4비트 2진수 입력 (0x0 ~ 0xF)
    output reg [6:0] seven_seg_out // 7세그먼트 출력 (g,f,e,d,c,b,a)
);

    // 7세그먼트의 각 LED 세그먼트 매핑
    // seven_seg_out[6] -> g (중앙)
    // seven_seg_out[5] -> f (왼쪽 상단)
    // seven_seg_out[4] -> e (왼쪽 하단)
    // seven_seg_out[3] -> d (하단)
    // seven_seg_out[2] -> c (오른쪽 하단)
    // seven_seg_out[1] -> b (오른쪽 상단)
    // seven_seg_out[0] -> a (상단)

    // 입력값에 따라 7세그먼트 출력을 결정하는 조합 회로
    always @(*) begin
        case (binary_in)
            4'h0: seven_seg_out = 7'b1000000; // 0
            4'h1: seven_seg_out = 7'b1111001; // 1
            4'h2: seven_seg_out = 7'b0100100; // 2
            4'h3: seven_seg_out = 7'b0110000; // 3
            4'h4: seven_seg_out = 7'b0011001; // 4
            4'h5: seven_seg_out = 7'b0010010; // 5
            4'h6: seven_seg_out = 7'b0000010; // 6
            4'h7: seven_seg_out = 7'b1111000; // 7
            4'h8: seven_seg_out = 7'b0000000; // 8
            4'h9: seven_seg_out = 7'b0010000; // 9
            4'hA: seven_seg_out = 7'b0001000; // A
            4'hB: seven_seg_out = 7'b0000011; // b
            4'hC: seven_seg_out = 7'b1000110; // C
            4'hD: seven_seg_out = 7'b0100001; // d
            4'hE: seven_seg_out = 7'b0000110; // E
            4'hF: seven_seg_out = 7'b0001110; // F
            default: seven_seg_out = 7'b1111111; // 그 외의 경우 모든 LED 끄기
        endcase
    end

endmodule