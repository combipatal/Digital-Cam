// OV7670 캡처 모듈
// 카메라로부터 픽셀 데이터를 캡처하여 블록 RAM에 저장
module ov7670_capture (
    input  wire        pclk,    // 픽셀 클럭 (카메라에서 제공)
    input  wire        vsync,   // 수직 동기화 신호
    input  wire        href,    // 수평 참조 신호 (라인 유효 신호)
    input  wire [7:0]  d,       // 픽셀 데이터 (8비트)
    output wire [16:0] addr,    // RAM 쓰기 주소
    output wire [11:0] dout,    // RAM 쓰기 데이터 (RGB565 -> 12비트)
    output reg         we       // RAM 쓰기 활성화 신호
);

    // 내부 레지스터들
    reg [15:0] d_latch = 16'h0000;        // 16비트 픽셀 데이터 래치 (RGB565)
    reg [16:0] address = 17'h00000;       // RAM 쓰기 주소 (76800개 픽셀)
    reg [1:0]  line = 2'b00;              // 현재 라인 카운터 (0-3)
    reg [6:0]  href_last = 7'b0000000;    // HREF 신호 히스토리 (7비트 시프트)
    reg        href_hold = 1'b0;          // HREF 이전 상태
    reg        latched_vsync = 1'b0;      // 래치된 VSYNC 신호
    reg        latched_href = 1'b0;       // 래치된 HREF 신호
    reg [7:0]  latched_d = 8'h00;         // 래치된 픽셀 데이터
    
    // 출력 신호 연결
    assign addr = address;  // RAM 쓰기 주소
    assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};  // RGB565 -> 12비트 변환
    
    always @(posedge pclk) begin
        // 주소 증가 - RAM에 쓰기가 완료되면 다음 주소로
        if (we == 1'b1) begin
            address <= address + 1'b1;
        end
        
        // HREF 상승 에지 감지 - 새로운 스캔 라인 시작
        if (href_hold == 1'b0 && latched_href == 1'b1) begin
            case (line)
                2'b00: line <= 2'b01;  // 라인 0 -> 1
                2'b01: line <= 2'b10;  // 라인 1 -> 2
                2'b10: line <= 2'b11;  // 라인 2 -> 3
                default: line <= 2'b00;  // 라인 3 -> 0 (순환)
            endcase
        end
        href_hold <= latched_href;  // HREF 이전 상태 저장
        
        // 카메라로부터 데이터 캡처 - RGB565 포맷
        if (latched_href == 1'b1) begin
            d_latch <= {d_latch[7:0], latched_d};  // 8비트씩 2번 받아서 16비트 완성
        end
        we <= 1'b0;  // 쓰기 신호 초기화
        
        // 새 프레임 감지 - VSYNC가 활성화되면 프레임 시작
        if (latched_vsync == 1'b1) begin
            address <= 17'h00000;      // 주소를 처음으로 리셋
            href_last <= 7'b0000000;   // HREF 히스토리 리셋
            line <= 2'b00;             // 라인 카운터 리셋
        end else begin
            // 쓰기 활성화 제어 - 320x240 해상도를 위해 2줄마다 캡처
            if (href_last[2] == 1'b1) begin  // HREF가 3클럭 동안 활성화되었을 때
                if (line[1] == 1'b1) begin   // 라인 2,3일 때만 캡처 (2줄마다)
                    we <= 1'b1;              // RAM 쓰기 활성화
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

// VGA 디스플레이용 주소 생성기 모듈
module Address_Generator (
    input  wire        CLK25,     // 25MHz VGA 클럭
    input  wire        enable,    // 주소 생성 활성화 신호
    input  wire        vsync,     // 수직 동기화 신호
    output wire [16:0] address    // RAM 읽기 주소
);

    reg [16:0] val = 17'h00000;  // 주소 카운터
    
    assign address = val;  // 주소 출력
    
    always @(posedge CLK25) begin
        if (enable == 1'b1) begin  // 활성 영역에서만 주소 증가
            // 320x240 = 76800 픽셀
            if (val < 76800) begin
                val <= val + 1'b1;  // 다음 픽셀 주소로
            end
        end
        
        // VSYNC에서 주소 리셋 - 새 프레임 시작
        if (vsync == 1'b0) begin
            val <= 17'h00000;  // 첫 번째 픽셀부터 시작
        end
    end
    
endmodule                                             