// OV7670 카메라 컨트롤러 모듈
// 카메라의 I2C 통신을 통해 레지스터 설정을 담당하는 최상위 모듈
module ov7670_controller (
    input  wire       clk_50,           // 50MHz 시스템 클럭
    input  wire       clk_24,           // 24MHz 시스템 클럭
    input  wire       resend,           // 설정 재시작 신호 (버튼 입력)
    output wire       config_finished,  // 설정 완료 신호 (LED 출력)
    output wire       sioc,             // I2C 클럭 신호
    inout  wire       siod,             // I2C 데이터 신호 (양방향)
    output wire       reset,            // 카메라 리셋 신호
    output wire       pwdn,             // 카메라 파워다운 신호
    output wire       xclk              // 카메라 클럭 신호 (25MHz)
);

    wire [15:0] command;       // I2C 명령어 (상위8비트: 레지스터주소, 하위8비트: 데이터)
    wire finished;             // 설정 완료 신호
    wire taken;                // I2C 전송 완료 신호
    wire send;                 // I2C 전송 시작 신호
    
    parameter CAMERA_ADDR = 8'h42;  // OV7670 카메라의 I2C 디바이스 주소 (쓰기용)
    
    // 신호 연결
    assign config_finished = finished;  // 설정 완료 신호를 LED로 출력
    assign send = ~finished;            // 설정이 완료되지 않았을 때만 전송 시작
    assign reset = 1'b1;                // 카메라를 정상 모드로 설정 (리셋 비활성화)
    assign pwdn = 1'b0;                 // 카메라 파워업 (파워다운 비활성화)
    assign xclk = clk_24;              // 24MHz 클럭을 카메라에 공급
    
    // I2C 송신기 인스턴스 - 실제 I2C 통신을 담당
    i2c_sender i2c_inst (
        .clk_50(clk_50),              // 50MHz 클럭
        .taken(taken),                // I2C 전송 완료 신호
        .siod(siod),                  // I2C 데이터 라인
        .sioc(sioc),                  // I2C 클럭 라인
        .send(send),                  // 전송 시작 신호
        .id(CAMERA_ADDR),             // 카메라 주소 (0x42)
        .data(command[15:8]),         // 레지스터 주소 (상위 8비트)
        .value(command[7:0])          // 레지스터 값 (하위 8비트)
    );
    
    // 레지스터 설정 인스턴스 - 카메라 레지스터 설정 시퀀스 관리
    ov7670_registers reg_inst (
        .clk_50(clk_50),              // 50MHz 클럭
        .advance(taken),              // I2C 전송 완료 시 다음 레지스터로 진행
        .command(command),            // 현재 설정할 레지스터 명령어
        .finished(finished),          // 모든 레지스터 설정 완료 신호
        .resend(resend)               // 설정 재시작 신호
    );
    
endmodule

// I2C 송신기 모듈 - I2C 프로토콜을 구현하여 카메라와 통신
module i2c_sender (
    input  wire       clk_50,     // 50MHz 클럭
    inout  wire       siod,       // I2C 데이터 라인 (양방향)
    output reg        sioc,       // I2C 클럭 라인
    output reg        taken,      // 전송 완료 신호
    input  wire       send,       // 전송 시작 신호
    input  wire [7:0] id,         // 디바이스 주소
    input  wire [7:0] data,       // 레지스터 주소
    input  wire [7:0] value       // 레지스터 값
);

    reg [7:0]  divider = 8'h01;        // 클럭 분주기 (I2C 속도 조절용)
    reg [31:0] busy_sr = 32'h0;        // I2C 상태 시프트 레지스터
    reg [31:0] data_sr = 32'hFFFFFFFF; // I2C 데이터 시프트 레지스터
    
    // SIOD 트라이스테이트 제어 - I2C 데이터 라인의 출력/입력 제어 , ACK 신호 판단
    assign siod = ((busy_sr[11:10] == 2'b10) || 
                   (busy_sr[20:19] == 2'b10) || 
                   (busy_sr[29:28] == 2'b10)) ? 1'bZ : data_sr[31];
    
    always @(posedge clk_50) begin
        taken <= 1'b0;  // 전송 완료 신호 초기화
        
        // I2C 전송이 비활성 상태일 때
        if (busy_sr[31] == 1'b0) begin
            sioc <= 1'b1;  // I2C 클럭을 HIGH로 설정 (대기 상태)
            if (send == 1'b1) begin  // 전송 요청이 있을 때
                if (divider == 8'h00) begin  // 분주기가 0이 되면 전송 시작
                    // I2C 데이터 패킷 구성: [시작비트][디바이스주소][ACK][레지스터주소][ACK][데이터][ACK][정지비트]
                    data_sr <= {3'b100, id, 1'b0, data, 1'b0, value, 1'b0, 2'b01};
                    // I2C 상태 시프트 레지스터 설정 (전송 상태로 전환)
                    busy_sr <= {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11};
                    taken <= 1'b1;  // 전송 시작 신호
                end else begin
                    divider <= divider + 1'b1;  // 분주기 증가
                end
            end
        end else begin  // I2C 전송이 활성 상태일 때
            // I2C 타이밍 상태 머신 - I2C 프로토콜의 클럭 신호 생성
            case ({busy_sr[31:29], busy_sr[2:0]})
                6'b111_111: sioc <= 1'b1;  // 시작 시퀀스 #1
                6'b111_110: sioc <= 1'b1;  // 시작 시퀀스 #2
                6'b111_100: sioc <= 1'b0;  // 시작 시퀀스 #3 (시작 조건)
                6'b110_000: sioc <= (divider[7:6] == 2'b00) ? 1'b0 : 1'b1;  // 종료 시퀀스 #1
                6'b100_000: sioc <= 1'b1;  // 종료 시퀀스 #2 (정지 조건)
                6'b000_000: sioc <= 1'b1;  // 대기 상태
                default: sioc <= (divider[7:6] == 2'b00) ? 1'b0 : 
                                (divider[7:6] == 2'b11) ? 1'b0 : 1'b1;  // 데이터 전송 중 클럭
                // divider[7:6] = 2'b00: 0~63   (64 클럭) ->  sioc <= 1'b0;
                // divider[7:6] = 2'b01: 64~127 (64 클럭) ->  sioc <= 1'b1;
                // divider[7:6] = 2'b10: 128~191(64 클럭) ->  sioc <= 1'b1;
                // divider[7:6] = 2'b11: 192~255(64 클럭) ->  sioc <= 1'b0;
            endcase

            // 분주기가 최대값에 도달하면 다음 비트로 진행
            if (divider == 8'hFF) begin // 255 클럭  (5.12us 마다 1비트 시프트)
                busy_sr <= {busy_sr[30:0], 1'b0};  // 상태 시프트 (왼쪽으로 1비트)
                data_sr <= {data_sr[30:0], 1'b1};  // 데이터 시프트 (왼쪽으로 1비트)
                divider <= 8'h00;  // 분주기 리셋
            end else begin
                divider <= divider + 1'b1;  // 분주기 증가
            end
        end
    end
    
endmodule

// OV7670 레지스터 설정 모듈 - 카메라 초기화를 위한 레지스터 값들을 순차적으로 제공
module ov7670_registers (
    input  wire        clk_50,     // 50MHz 클럭
    input  wire        resend,     // 설정 재시작 신호
    input  wire        advance,    // 다음 레지스터로 진행 신호
    output reg  [15:0] command,    // 현재 설정할 레지스터 명령어
    output wire        finished    // 모든 설정 완료 신호
);

    reg [7:0] address = 8'h00;  // 현재 설정 중인 레지스터 인덱스
    
    assign finished = (command == 16'hFFFF);  // 0xFFFF이면 설정 완료
    
    always @(posedge clk_50) begin
        // 주소 관리
        if (resend) begin
            address <= 8'h00;  // 재시작 시 첫 번째 레지스터부터 시작
        end else if (advance) begin
            address <= address + 1'b1;  // I2C 전송 완료 시 다음 레지스터로
        end
        
        // 레지스터 설정 시퀀스 - OV7670 카메라 초기화를 위한 레지스터 값들
        case (address)
            8'h00: command <= 16'h1280; // COM7: 카메라 리셋
            
            // --- 화이트 밸런스 수동 설정 (붉은기 감소) ---
            8'h01: command <= 16'h0180; // BLUE: 파란색 채널 게인 (기본값)
            8'h02: command <= 16'h0260; // RED:  빨간색 채널 게인 (낮춤)
            8'h03: command <= 16'h13E7; // COM8: AWB 비활성화, AGC/AEC 활성화
            // --- 화이트 밸런스 설정 끝 ---
            
            8'h04: command <= 16'h1204; // COM7: 크기 및 RGB 출력 설정
            8'h05: command <= 16'h1100; // CLKRC: 클럭 프리스케일러
            8'h06: command <= 16'h0C00; // COM3: 일반 설정
            8'h07: command <= 16'h3E00; // COM14: 스케일링 설정
            8'h08: command <= 16'h0400; // COM1: 수평 오프셋
            8'h09: command <= 16'h4010; // COM15: RGB 565 포맷 설정
            8'h0A: command <= 16'h3A04; // TSLB: YUV 순서 설정
            8'h0B: command <= 16'h1438; // COM9: AGC 게인 설정
            
            // --- 색상 매트릭스 설정 (YUV to RGB 변환) ---
            8'h0C: command <= 16'h4F40; // MTX1: 색상 매트릭스 계수 1
            8'h0D: command <= 16'h5034; // MTX2: 색상 매트릭스 계수 2
            8'h0E: command <= 16'h510C; // MTX3: 색상 매트릭스 계수 3
            8'h0F: command <= 16'h5217; // MTX4: 색상 매트릭스 계수 4
            8'h10: command <= 16'h5329; // MTX5: 색상 매트릭스 계수 5
            8'h11: command <= 16'h5440; // MTX6: 색상 매트릭스 계수 6
            
            8'h12: command <= 16'h581E; // MTXS: 색상 매트릭스 스케일
            8'h13: command <= 16'h3DC0; // COM13: 감마 설정
            8'h14: command <= 16'h1711; // HSTART: 수평 시작 위치
            8'h15: command <= 16'h1861; // HSTOP: 수평 종료 위치
            8'h16: command <= 16'h32A4; // HREF: 수평 참조 설정
            8'h17: command <= 16'h1903; // VSTART: 수직 시작 위치
            8'h18: command <= 16'h1A7B; // VSTOP: 수직 종료 위치
            8'h19: command <= 16'h030A; // VREF: 수직 참조 설정
            8'h1A: command <= 16'h0E61; // COM5: 수직 동기화 설정
            8'h1B: command <= 16'h0F4B; // COM6: 수직 동기화 설정
            8'h1C: command <= 16'h1602; // 일반 설정
            8'h1D: command <= 16'h1E10; // MVFP: 미러/플립 설정 (상하반전만 활성화)
            8'h1E: command <= 16'h2102; // 일반 설정
            8'h1F: command <= 16'h2291; // 일반 설정
            8'h20: command <= 16'h2907; // 일반 설정
            8'h21: command <= 16'h330B; // 일반 설정
            8'h22: command <= 16'h350B; // 일반 설정
            8'h23: command <= 16'h371D; // 일반 설정
            8'h24: command <= 16'h3871; // 일반 설정
            8'h25: command <= 16'h392A; // 일반 설정
            8'h26: command <= 16'h3C78; // COM12: 수직 동기화 설정
            8'h27: command <= 16'h4D40; // 일반 설정
            8'h28: command <= 16'h4E20; // 일반 설정
            8'h29: command <= 16'h6900; // GFIX: 그린 게인 고정
            8'h2A: command <= 16'h6B4A; // 일반 설정
            8'h2B: command <= 16'h7410; // 일반 설정
            8'h2C: command <= 16'h8D4F; // 일반 설정
            8'h2D: command <= 16'h8E00; // 일반 설정
            8'h2E: command <= 16'h8F00; // 일반 설정
            8'h2F: command <= 16'h9000; // 일반 설정
            8'h30: command <= 16'h9100; // 일반 설정
            8'h31: command <= 16'h9600; // 일반 설정
            8'h32: command <= 16'h9A00; // 일반 설정
            8'h33: command <= 16'hB084; // 일반 설정
            8'h34: command <= 16'hB10C; // 일반 설정
            8'h35: command <= 16'hB20E; // 일반 설정
            8'h36: command <= 16'hB382; // 일반 설정
            8'h37: command <= 16'hB80A; // 일반 설정
            8'h38: command <= 16'h5640; // CONTRAS: 대비 설정
			8'h39: command <= 16'h5500; // BRIGHT: 밝기 설정 (기본값 0x00)
			8'h3B: command <= 16'h3B0A; // COM11: 밴딩 필터 auto
			8'h41: command <= 16'h4118; // COM16: de-noise auto + AWB gain enable
			8'h4C: command <= 16'h4C14; // DNSTH: de-noise 기본 세기
			8'h3F: command <= 16'h3F10; // EDGE: 약하게(필요시 0x00)
			8'h76: command <= 16'h76C1; // REG76: 흑/백 픽셀 보정 enable
			8'h77: command <= 16'h7710; // REG77: de-noise offset 기본
			default: command <= 16'hFFFF;  // 설정 완료 표시
        endcase
    end
endmodule