// OV7670 캡처 모듈
// 카메라로부터 픽셀 데이터를 캡처하여 블록 RAM에 저장
module ov7670_capture (
    input  wire        pclk,    // 픽셀 클럭 (카메라에서 제공)
    input  wire        vsync,   // 수직 동기화 신호
    input  wire        href,    // 수평 참조 신호 (라인 유효 신호)
    input  wire [7:0]  d,       // 픽셀 데이터 (8비트)
    output wire [16:0] addr,    // RAM 쓰기 주소
    output wire [15:0] dout,    // RAM 쓰기 데이터 (RGB565 16비트)
    output reg         we       // RAM 쓰기 활성화 신호
);

    // 크롭 파라미터 (필요 시 조정)
    // 좌/우/상/하 테두리 픽셀을 버리고 블랙으로 채움
    parameter integer H_SKIP_LEFT   = 0;  // 0..319
    parameter integer H_SKIP_RIGHT  = 0;  // 0..319
    parameter integer V_SKIP_TOP    = 0;  // 0..239
    parameter integer V_SKIP_BOTTOM = 0;  // 0..239

    // 내부 레지스터들
    reg [15:0] d_latch = 16'h0000;        // 16비트 픽셀 데이터 래치 (RGB565)
    reg [16:0] address = 17'h00000;       // RAM 쓰기 주소 (76800개 픽셀)
    reg [8:0]  h_count = 9'd0;            // 라인 내 픽셀 인덱스 0..319
    reg [8:0]  v_count = 9'd0;            // 프레임 내 라인 인덱스 0..239
    reg [1:0]  line = 2'b00;              // 현재 라인 카운터 (0-3)
    reg        href_hold = 1'b0;          // HREF 이전 상태
    reg [6:0]  href_last = 7'b0000000;    // HREF 신호 히스토리 (7비트 시프트)
    reg        latched_vsync = 1'b0;      // 래치된 VSYNC 신호
    reg        latched_href = 1'b0;       // 래치된 HREF 신호
    reg [7:0]  latched_d = 8'h00;         // 래치된 픽셀 데이터
    
    // 출력 신호 연결
    assign addr = address;  // RAM 쓰기 주소
    // 크롭 범위 밖은 블랙으로 기록하기 위한 선택 신호
    reg write_black = 1'b0;
    assign dout = write_black ? 16'h0000 : d_latch;  // 범위 밖은 블랙
    
    always @(posedge pclk) begin
        // 주소는 (v*320 + h)로 직접 계산하여 기록 시에만 갱신
        if (we == 1'b1) begin
            // 320 = 256 + 64
            address <= ({8'd0, v_count} << 8) + ({8'd0, v_count} << 6) + {8'd0, h_count};
        end
        
        // HREF 상승 에지 감지 - 새로운 스캔 라인 시작
        if (href_hold == 1'b0 && latched_href == 1'b1) begin
            h_count <= 9'd0;              // 가로 인덱스 리셋
            case (line)
                2'b00: line <= 2'b01;  // 라인 0 -> 1
                2'b01: line <= 2'b10;  // 라인 1 -> 2
                2'b10: line <= 2'b11;  // 라인 2 -> 3
                default: line <= 2'b00;  // 라인 3 -> 0 (순환)
            endcase
        end
        // HREF 하강 에지 감지 - 라인 종료 시 세로 인덱스 증가 (다운샘플 라인에 대해서만)
        if (href_hold == 1'b1 && latched_href == 1'b0) begin
            if (line[1] == 1'b1) begin
                if (v_count < 9'd239) v_count <= v_count + 1'b1;
            end
        end
        href_hold <= latched_href;  // HREF 이전 상태 저장
        
        // 카메라로부터 데이터 캡처 - RGB565 포맷
        if (latched_href == 1'b1) begin
            d_latch <= {d_latch[7:0], latched_d};  // 8비트씩 2번 받아서 16비트 완성
        end
        // 기본값: 쓰기 비활성
        we <= 1'b0;
        
        // 새 프레임 감지 - VSYNC가 활성화되면 프레임 시작(주소/상태 리셋)
        if (latched_vsync == 1'b1) begin
            address <= 17'h00000;      // 주소를 처음으로 리셋
            href_last <= 7'b0000000;   // HREF 히스토리 리셋
            line <= 2'b00;             // 라인 카운터 리셋
            h_count <= 9'd0;           // 가로 인덱스 리셋
            v_count <= 9'd0;           // 세로 인덱스 리셋
            we <= 1'b0;                // 프레임 경계에서는 쓰기 비활성
        end else begin
            // 쓰기 활성화 제어 - 320x240 해상도를 위해 2줄마다 캡처
            if (href_last[2] == 1'b1) begin  // HREF가 3클럭 동안 활성화되었을 때 (수평 다운샘플 트리거)
                if (line[1] == 1'b1 && h_count < 9'd320 && v_count < 9'd240) begin   // 다운샘플 라인 & 범위 내
                    // 주소는 (v*320 + h)
                    address <= ({8'd0, v_count} << 8) + ({8'd0, v_count} << 6) + {8'd0, h_count};
                    // 크롭 범위 계산
                    // 허용 수평: [H_SKIP_LEFT .. 319-H_SKIP_RIGHT]
                    // 허용 수직: [V_SKIP_TOP  .. 239-V_SKIP_BOTTOM]
                    if ((h_count >= H_SKIP_LEFT[8:0]) && (h_count <= (9'd319 - H_SKIP_RIGHT[8:0])) &&
                        (v_count >= V_SKIP_TOP[8:0])  && (v_count <= (9'd239 - V_SKIP_BOTTOM[8:0]))) begin
                        write_black <= 1'b0;  // 유효 범위: 원본 픽셀 기록
                    end else begin
                        write_black <= 1'b1;  // 범위 밖: 블랙 기록
                    end
                    we <= 1'b1;              // RAM 쓰기 1사이클
                    // 다음 픽셀로 진행
                    if (h_count < 9'd319) begin
                        h_count <= h_count + 1'b1;
                    end
                end else begin
                    we <= 1'b0;              // 범위 밖이면 억제
                    write_black <= 1'b0;
                end
                href_last <= 7'b0000000;     // HREF 히스토리 리셋
            end else begin
                href_last <= {href_last[5:0], latched_href};  // HREF 히스토리 시프트
            end
        end
    end
    
    // 입력 신호 래치 - 픽셀 클럭의 하강 에지에서 입력을 래치
    always @(negedge pclk) begin
        latched_d <= d;           // 픽셀 데이터 래치
        latched_href <= href;     // HREF 신호 래치
        latched_vsync <= vsync;   // VSYNC 신호 래치
    end
    
endmodule
