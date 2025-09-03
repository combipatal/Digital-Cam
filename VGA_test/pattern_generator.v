

// ============================================
// 패턴 생성기
// h_count,v_count 값에 따라 빨강/초록/파랑 패널 채움
// SW 스위치를 이용해서 다양한 테스트 패턴을 표시 가능
// ============================================
module pattern_generator (
    input wire clk,
    input wire reset_n,
    input wire [9:0] h_count,   // 현재 X 좌표
    input wire [9:0] v_count,   // 현재 Y 좌표
    input wire video_on,        // 화면 표시 가능 여부
    input wire [17:0] sw,       // 스위치 입력
    output reg [7:0] red,
    output reg [7:0] green,
    output reg [7:0] blue
);

    wire [2:0] pattern_sel;
    assign pattern_sel = sw[2:0];  // 하위 3비트로 패턴 종류 선택

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            red   <= 8'd0;
            green <= 8'd0;
            blue  <= 8'd0;
        end
        else if (video_on) begin
            case (pattern_sel)
                3'b000: begin  // 컬러 바 패턴
                    if (h_count < 80)       begin red<=255; green<=255; blue<=255; end // White
                    else if (h_count < 160) begin red<=255; green<=255; blue<=0;   end // Yellow
                    else if (h_count < 240) begin red<=0;   green<=255; blue<=255; end // Cyan
                    else if (h_count < 320) begin red<=0;   green<=255; blue<=0;   end // Green
                    else if (h_count < 400) begin red<=255; green<=0;   blue<=255; end // Magenta
                    else if (h_count < 480) begin red<=255; green<=0;   blue<=0;   end // Red
                    else if (h_count < 560) begin red<=0;   green<=0;   blue<=255; end // Blue
                    else                    begin red<=0;   green<=0;   blue<=0;   end // Black
                end
                
                3'b001: begin  // X 방향 그라데이션
                    red   <= h_count[9:2]; // 상위 비트 → 큰 변화
                    green <= h_count[8:1];
                    blue  <= h_count[7:0]; // 하위 비트 → 미세 변화
                end
                
                3'b010: begin  // Y 방향 그라데이션
                    red   <= v_count[8:1];
                    green <= v_count[9:2];
                    blue  <= v_count[7:0];
                end
                
                3'b011: begin  // 체커보드 패턴
                    if (h_count[5] ^ v_count[5]) begin
                        red<=255; green<=255; blue<=255; // 하얀 블록
                    end else begin
                        red<=0; green<=0; blue<=0;       // 검은 블록
                    end
                end
                
                3'b100: begin  // RGB 스위치 직접 제어
                    red   <= {8{sw[17]}}; // SW[17] = 전체 빨강 on/off
                    green <= {8{sw[16]}};
                    blue  <= {8{sw[15]}};
                end
                
                3'b101: begin  // 십자 패턴
                    if ((h_count >= 310 && h_count <= 330) || 
                        (v_count >= 230 && v_count <= 250)) begin
                        red<=255; green<=0; blue<=0;     // 빨간 십자
                    end else begin
                        red<=0; green<=0; blue<=255;     // 파란 배경
                    end
                end
                
                3'b110: begin  // 테두리 패턴
                    if (h_count < 10 || h_count >= 630 || 
                        v_count < 10 || v_count >= 470) begin
                        red<=255; green<=255; blue<=0;   // 노란색 테두리
                    end else begin
                        red<=0; green<=64; blue<=128;    // 진한 청록색 내부
                    end
                end
                
                default: begin  // 기본 단색 (파란색 느낌)
                    red<=64; green<=128; blue<=255;
                end
            endcase
        end
        else begin
            // 표시 구간 아닐 때는 화면 off
            red<=0; green<=0; blue<=0;
        end
    end
endmodule