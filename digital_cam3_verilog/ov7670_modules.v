// OV7670 카메라 관련 모듈들을 하나의 파일로 통합

// OV7670 카메라 캡처 모듈
module ov7670_capture(
  input wire pclk,
  input wire vsync,
  input wire href,
  input wire [7:0] d,
  output wire [16:0] addr,
  output wire [11:0] dout,
  output wire we
);

  reg [15:0] d_latch = 16'b0;
  reg [16:0] address = 17'b0;
  reg [1:0] line = 2'b0;
  reg [6:0] href_last = 7'b0;
  reg we_reg = 1'b0;
  reg href_hold = 1'b0;
  reg latched_vsync = 1'b0;
  reg latched_href = 1'b0;
  reg [7:0] latched_d = 8'b0;

  // 출력 할당
  assign addr = address;
  assign we = we_reg;
  assign dout = {d_latch[15:12], d_latch[10:7], d_latch[4:1]};

  // 캡처 프로세스
  always @(posedge pclk) begin
    if (we_reg) begin
      address <= address + 1;
    end

    // href 신호의 상승 에지 감지 - 스캔 라인의 시작
    if (href_hold == 1'b0 && latched_href == 1'b1) begin
      case (line)
        2'b00: line <= 2'b01;
        2'b01: line <= 2'b10;
        2'b10: line <= 2'b11;
        default: line <= 2'b00;
      endcase
    end
    href_hold <= latched_href;

    // 카메라에서 데이터 캡처, 12비트 RGB
    if (latched_href == 1'b1) begin
      d_latch <= {d_latch[7:0], latched_d};
    end
    we_reg <= 1'b0;

    // 새 화면이 시작되는지 확인
    if (latched_vsync == 1'b1) begin
      address <= 17'b0;
      href_last <= 7'b0;
      line <= 2'b0;
    end else begin
      // 픽셀을 캡처해야 할 때 쓰기 활성화
      if (href_last[2] == 1'b1) begin
        if (line[1] == 1'b1) begin
          we_reg <= 1'b1;
        end
        href_last <= 7'b0;
      end else begin
        href_last <= {href_last[5:0], latched_href};
      end
    end
  end

  // 하강 에지에서 데이터 및 제어 신호 래칭
  always @(negedge pclk) begin
    latched_d <= d;
    latched_href <= href;
    latched_vsync <= vsync;
  end

endmodule

// I2C 송신기 모듈
module i2c_sender(
  input wire clk,
  inout wire siod,
  output reg sioc,
  output reg taken,
  input wire send,
  input wire [7:0] id,
  input wire [7:0] reg_addr,
  input wire [7:0] value
);

  reg [7:0] divider = 8'h01;  // 254 사이클 대기
  reg [31:0] busy_sr = 32'b0;
  reg [31:0] data_sr = 32'hFFFFFFFF;

  // SIOD 출력 제어
  assign siod = (busy_sr[11:10] == 2'b10 ||
                busy_sr[20:19] == 2'b10 ||
                busy_sr[29:28] == 2'b10) ? 1'bz : data_sr[31];

  always @(posedge clk) begin
    taken <= 1'b0;
    
    if (busy_sr[31] == 1'b0) begin
      sioc <= 1'b1;
      if (send == 1'b1) begin
        if (divider == 8'h00) begin
          data_sr <= {3'b100, id, 1'b0, reg_addr, 1'b0, value, 1'b0, 2'b01};
          busy_sr <= {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11};
          taken <= 1'b1;
        end else begin
          divider <= divider + 1;  // 처음에만 실행
        end
      end
    end else begin
      case ({busy_sr[31:29], busy_sr[2:0]})
        6'b111_111: begin  // 시작 시퀀스 #1
          case (divider[7:6])
            2'b00: sioc <= 1'b1;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b1;
          endcase
        end
        
        6'b111_110: begin  // 시작 시퀀스 #2
          case (divider[7:6])
            2'b00: sioc <= 1'b1;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b1;
          endcase
        end
        
        6'b111_100: begin  // 시작 시퀀스 #3
          case (divider[7:6])
            2'b00: sioc <= 1'b0;
            2'b01: sioc <= 1'b0;
            2'b10: sioc <= 1'b0;
            default: sioc <= 1'b0;
          endcase
        end
        
        6'b110_000: begin  // 종료 시퀀스 #1
          case (divider[7:6])
            2'b00: sioc <= 1'b0;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b1;
          endcase
        end
        
        6'b100_000: begin  // 종료 시퀀스 #2
          case (divider[7:6])
            2'b00: sioc <= 1'b1;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b1;
          endcase
        end
        
        6'b000_000: begin  // 유휴 상태
          case (divider[7:6])
            2'b00: sioc <= 1'b1;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b1;
          endcase
        end
        
        default: begin
          case (divider[7:6])
            2'b00: sioc <= 1'b0;
            2'b01: sioc <= 1'b1;
            2'b10: sioc <= 1'b1;
            default: sioc <= 1'b0;
          endcase
        end
      endcase

      if (divider == 8'hFF) begin
        busy_sr <= {busy_sr[30:0], 1'b0};
        data_sr <= {data_sr[30:0], 1'b1};
        divider <= 8'b0;
      end else begin
        divider <= divider + 1;
      end
    end
  end
endmodule

// OV7670 레지스터 설정 모듈
module ov7670_registers(
  input wire clk,
  input wire resend,
  input wire advance,
  output wire [15:0] command,
  output wire finished
);

  reg [15:0] sreg;
  reg [7:0] address = 8'b0;

  assign command = sreg;
  assign finished = (sreg == 16'hFFFF) ? 1'b1 : 1'b0;

  always @(posedge clk) begin
    if (resend == 1'b1) begin
      address <= 8'b0;
    end
    else if (advance == 1'b1) begin
      address <= address + 1;
    end

    case (address)
      8'h00: sreg <= 16'h1280;  // COM7 Reset
      8'h01: sreg <= 16'h1280;  // COM7 Reset
      8'h02: sreg <= 16'h1204;  // COM7 크기 및 RGB 출력
      8'h03: sreg <= 16'h1100;  // CLKRC Prescaler - Fin/(1+1)
      8'h04: sreg <= 16'h0C00;  // COM3 다양한 설정
      8'h05: sreg <= 16'h3E00;  // COM14 PCLK 스케일링 비활성화
      
      8'h06: sreg <= 16'h8C00;  // RGB444 RGB 형식 설정
      8'h07: sreg <= 16'h0400;  // COM1 CCIR601 없음
      8'h08: sreg <= 16'h4010;  // COM15 0-255 출력, RGB 565
      8'h09: sreg <= 16'h3a04;  // TSLB UV 순서 설정
      8'h0A: sreg <= 16'h1438;  // COM9 AGC 상한
      8'h0B: sreg <= 16'h4f40;  // MTX1 색상 변환 매트릭스
      8'h0C: sreg <= 16'h5034;  // MTX2 색상 변환 매트릭스
      8'h0D: sreg <= 16'h510C;  // MTX3 색상 변환 매트릭스
      8'h0E: sreg <= 16'h5217;  // MTX4 색상 변환 매트릭스
      8'h0F: sreg <= 16'h5329;  // MTX5 색상 변환 매트릭스
      8'h10: sreg <= 16'h5440;  // MTX6 색상 변환 매트릭스
      8'h11: sreg <= 16'h581e;  // MTXS 매트릭스 부호 및 자동 대비
      8'h12: sreg <= 16'h3dc0;  // COM13 GAMMA 및 UV 자동 조정 켜기
      8'h13: sreg <= 16'h1100;  // CLKRC Prescaler - Fin/(1+1)
      
      8'h14: sreg <= 16'h1711;  // HSTART HREF 시작 (상위 8비트)
      8'h15: sreg <= 16'h1861;  // HSTOP HREF 종료 (상위 8비트)
      8'h16: sreg <= 16'h32A4;  // HREF 에지 오프셋 및 HSTART/HSTOP 하위 3비트
      
      8'h17: sreg <= 16'h1903;  // VSTART VSYNC 시작 (상위 8비트)
      8'h18: sreg <= 16'h1A7b;  // VSTOP VSYNC 종료 (상위 8비트)
      8'h19: sreg <= 16'h030a;  // VREF VSYNC 하위 2비트
      
      8'h1A: sreg <= 16'h0e61;  // COM5(0x0E) 0x61
      8'h1B: sreg <= 16'h0f4b;  // COM6(0x0F) 0x4B
      
      8'h1C: sreg <= 16'h1602;  //
      8'h1D: sreg <= 16'h1e37;  // MVFP(0x1E) 이미지 뒤집기 및 미러링
      
      8'h1E: sreg <= 16'h2102;
      8'h1F: sreg <= 16'h2291;
      
      8'h20: sreg <= 16'h2907;
      8'h21: sreg <= 16'h330b;
      
      8'h22: sreg <= 16'h350b;
      8'h23: sreg <= 16'h371d;
      
      8'h24: sreg <= 16'h3871;
      8'h25: sreg <= 16'h392a;
      
      8'h26: sreg <= 16'h3c78;  // COM12(0x3C) 0x78
      8'h27: sreg <= 16'h4d40;
      
      8'h28: sreg <= 16'h4e20;
      8'h29: sreg <= 16'h6900;  // GFIX(0x69) 0x00
      
      8'h2A: sreg <= 16'h6b4a;
      8'h2B: sreg <= 16'h7410;
      
      8'h2C: sreg <= 16'h8d4f;
      8'h2D: sreg <= 16'h8e00;
      
      8'h2E: sreg <= 16'h8f00;
      8'h2F: sreg <= 16'h9000;
      
      8'h30: sreg <= 16'h9100;
      8'h31: sreg <= 16'h9600;
      
      8'h32: sreg <= 16'h9a00;
      8'h33: sreg <= 16'hb084;
      
      8'h34: sreg <= 16'hb10c;
      8'h35: sreg <= 16'hb20e;
      
      8'h36: sreg <= 16'hb382;
      8'h37: sreg <= 16'hb80a;
      
      default: sreg <= 16'hffff;
    endcase
  end
endmodule

// OV7670 컨트롤러 모듈
module ov7670_controller(
  input wire clk,
  input wire resend,
  inout wire siod,
  output wire config_finished,
  output wire sioc,
  output wire reset,
  output wire pwdn,
  output wire xclk
);

  reg sys_clk = 1'b0;
  wire [15:0] command;
  wire finished;
  wire taken;
  wire send;
  
  // 카메라 쓰기 ID
  localparam [7:0] camera_address = 8'h42;
  
  // 출력 할당
  assign config_finished = finished;
  assign send = ~finished;
  
  // I2C 송신기 인스턴스
  i2c_sender Inst_i2c_sender(
    .clk(clk),
    .taken(taken),
    .siod(siod),
    .sioc(sioc),
    .send(send),
    .id(camera_address),
    .reg_addr(command[15:8]),
    .value(command[7:0])
  );

  // 상태 제어
  assign reset = 1'b1;  // 정상 모드
  assign pwdn = 1'b0;   // 장치 전원 켜기
  assign xclk = sys_clk;
  
  // 레지스터 인스턴스
  ov7670_registers Inst_ov7670_registers(
    .clk(clk),
    .advance(taken),
    .command(command),
    .finished(finished),
    .resend(resend)
  );

  // 클럭 생성
  always @(posedge clk) begin
    sys_clk <= ~sys_clk;
  end

endmodule
