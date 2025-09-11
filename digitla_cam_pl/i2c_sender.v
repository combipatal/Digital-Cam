// I2C 송신기 모듈 - OV7670 카메라 모듈에 명령 전송
module i2c_sender(
  input wire clk,
  input wire rst_n,          // 활성화 낮음 리셋
  inout wire siod,
  output reg sioc,
  output reg taken,
  input wire send,
  input wire [7:0] id,       // 카메라 장치 ID
  input wire [7:0] reg_addr, // 레지스터 주소
  input wire [7:0] value     // 레지스터 값
);

  // 내부 신호
  reg [7:0] divider;
  reg [31:0] busy_sr;
  reg [31:0] data_sr;
  
  // siod 출력 제어
  assign siod = (busy_sr[11:10] == 2'b10 || 
                 busy_sr[20:19] == 2'b10 || 
                 busy_sr[29:28] == 2'b10) ? 1'bz : data_sr[31];
  
  // I2C 통신 로직
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      taken <= 1'b0;
      sioc <= 1'b1;
      busy_sr <= 32'b0;
      data_sr <= 32'h00000000;
      divider <= 8'h01;  // 초기 지연을 위한 값
    end else begin
      taken <= 1'b0;
      
      if (busy_sr[31] == 1'b0) begin
        sioc <= 1'b1;
        if (send == 1'b1) begin
          if (divider == 8'h00) begin
            data_sr <= {3'b100, id, 1'b0, reg_addr, 1'b0, value, 1'b0, 2'b01};
            busy_sr <= {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11};
            taken <= 1'b1;
          end else begin
            divider <= divider + 1'b1; // 전원 공급 시에만 발생
          end
        end
      end else begin
        // I2C 프로토콜에 따른 시퀀스 제어
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
          divider <= 8'h00;
        end else begin
          divider <= divider + 1'b1;
        end
      end
    end
  end

endmodule