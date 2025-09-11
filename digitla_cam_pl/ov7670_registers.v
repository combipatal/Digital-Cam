// OV7670 레지스터 설정 모듈
// OV7670 카메라의 레지스터 값을 설정하는 모듈입니다.
// 리눅스 커널의 OV7670.c 및 다른 소스를 참조하여 작성되었습니다.
module ov7670_registers(
  input wire clk,         // 시스템 클록
  input wire rst_n,       // 활성화 낮음 리셋 신호
  input wire resend,      // 모든 레지스터 값을 다시 전송하는 신호
  input wire advance,     // 다음 레지스터로 진행하는 신호
  output reg [15:0] command,  // 레지스터 주소와 값 쌍 (상위 8비트: 주소, 하위 8비트: 값)
  output wire finished    // 모든 레지스터 설정 완료 신호
);

  // 내부 신호
  reg [7:0] address;     // 현재 레지스터 주소
  
  // 레지스터 설정이 완료되면 finished 신호 활성화
  // 0xFFFF는 레지스터 설정 종료를 나타내는 특수값
  assign finished = (command == 16'hFFFF) ? 1'b1 : 1'b0;
  
  // 레지스터 주소 관리
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // 리셋이 활성화되면 주소를 0으로 초기화
      address <= 8'h00;
    end else if (resend) begin
      // resend 신호가 있으면 처음부터 다시 시작
      address <= 8'h00;
    end else if (advance) begin
      // advance 신호가 있으면 다음 주소로 이동
      address <= address + 1'b1;
    end
  end
  
  // 레지스터 값 설정
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // 리셋 시 기본값
      command <= 16'h1280;  // COM7 리셋
    end else begin
      // 레지스터 주소와 값 쌍 정의
      case (address)
        8'h00: command <= 16'h1280;  // COM7 리셋
        8'h01: command <= 16'h1280;  // COM7 리셋
        8'h02: command <= 16'h1204;  // COM7 크기 & RGB 출력
        8'h03: command <= 16'h1100;  // CLKRC 프리스케일러 - Fin/(1+1)
        8'h04: command <= 16'h0C00;  // COM3 스케일링 활성화, 다른 모든 기능 비활성화
        8'h05: command <= 16'h3E00;  // COM14 PCLK 스케일링 비활성화
        
        8'h06: command <= 16'h8C00;  // RGB444 RGB 형식 설정
        8'h07: command <= 16'h0400;  // COM1 CCIR601 없음
        8'h08: command <= 16'h0D60;  // COM4(0x0D) HS 신호 형식 설정
        8'h09: command <= 16'h4010;  // COM15 전체 0-255 출력, RGB 565
        8'h0A: command <= 16'h3A04;  // TSLB UV 순서 설정, 윈도우 자동 리셋 비활성화
        8'h0B: command <= 16'h1438;  // COM9 AGC 천장
        8'h0C: command <= 16'h4F40;  // MTX1 색상 변환 행렬
        8'h0D: command <= 16'h5034;  // MTX2 색상 변환 행렬
        8'h0E: command <= 16'h510C;  // MTX3 색상 변환 행렬
        8'h0F: command <= 16'h5217;  // MTX4 색상 변환 행렬
        8'h10: command <= 16'h5329;  // MTX5 색상 변환 행렬
        8'h11: command <= 16'h5440;  // MTX6 색상 변환 행렬
        8'h12: command <= 16'h581E;  // MTXS 행렬 부호 및 자동 대비
        8'h13: command <= 16'h3DC0;  // COM13 감마 및 UV 자동 조정 활성화
        8'h14: command <= 16'h1100;  // CLKRC 프리스케일러 - Fin/(1+1)
        
        8'h15: command <= 16'h1711;  // HSTART HREF 시작 (상위 8비트)
        8'h16: command <= 16'h1861;  // HSTOP HREF 정지 (상위 8비트)
        8'h17: command <= 16'h32A4;  // HREF 에지 오프셋 및 HSTART/HSTOP 하위 3비트
        
        8'h18: command <= 16'h1903;  // VSTART VSYNC 시작 (상위 8비트)
        8'h19: command <= 16'h1A7B;  // VSTOP VSYNC 정지 (상위 8비트)
        8'h1A: command <= 16'h030A;  // VREF VSYNC 하위 2비트
        
        8'h1B: command <= 16'h0E61;  // COM5(0x0E) 0x61
        8'h1C: command <= 16'h0F4B;  // COM6(0x0F) 0x4B
        
        8'h1D: command <= 16'h1602;  
        8'h1E: command <= 16'h1E37;  // MVFP (0x1E) 0x07 - 이미지 플립 및 미러링 0x3x
        
        8'h1F: command <= 16'h2102;
        8'h20: command <= 16'h2291;
        
        8'h21: command <= 16'h2907;
        8'h22: command <= 16'h330B;
        
        8'h23: command <= 16'h350B;
        8'h24: command <= 16'h371D;
        
        8'h25: command <= 16'h3871;
        8'h26: command <= 16'h392A;
        
        8'h27: command <= 16'h3C78;  // COM12 (0x3C) 0x78
        8'h28: command <= 16'h4D40;
        
        8'h29: command <= 16'h4E20;
        8'h2A: command <= 16'h6900;  // GFIX (0x69) 0x00
        
        8'h2B: command <= 16'h6B4A;
        8'h2C: command <= 16'h7410;
        
        8'h2D: command <= 16'h8D4F;
        8'h2E: command <= 16'h8E00;
        
        8'h2F: command <= 16'h8F00;
        8'h30: command <= 16'h9000;
        
        8'h31: command <= 16'h9100;
        8'h32: command <= 16'h9600;
        
        8'h33: command <= 16'h9A00;
        8'h34: command <= 16'hB084;
        
        8'h35: command <= 16'hB10C;
        8'h36: command <= 16'hB20E;
        
        8'h37: command <= 16'hB382;
        8'h38: command <= 16'hB80A;
        
        default: command <= 16'hFFFF;  // 모든 설정 완료
      endcase
    end
  end

endmodule