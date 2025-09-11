// ov7670_registers.v (수정본: 640x480 VGA, RGB565 설정)

module ov7670_registers (
    input clk,
    input resend,
    input advance,
    output reg [15:0] command,
    output finished
);

    reg [7:0] address = 8'b0;
    
    // [수정] VGA 설정에 맞춰 마지막 주소 변경
    assign finished = (address == 8'd56); 

    always @(posedge clk) begin
        if (resend) begin
            address <= 8'b0;
        end else if (advance && !finished) begin
            address <= address + 1;
        end

        case (address)
            // COM7: 리셋 및 VGA, RGB 포맷 선택
            8'd0: command <= 16'h1280; // COM7 Reset
            8'd1: command <= 16'h1280; // COM7 Reset (안정성을 위해 한번 더)
            8'd2: command <= 16'h1204; // COM7: VGA, RGB

            // COM15: 출력 범위 및 RGB565 포맷 선택
            8'd3: command <= 16'h4010; // COM15: Full 0-255, RGB565

            // 기본 클럭 및 타이밍 설정
            8'd4: command <= 16'h1101; // CLKRC: Internal clock pre-scaler
            8'd5: command <= 16'h0C00; // COM3
            8'd6: command <= 16'h3E00; // COM14
            8'd7: command <= 16'h0400; // COM1
            8'd8: command <= 16'h3a04; // TSLB

            // VGA 해상도 타이밍 설정 (Standard VGA values)
            8'd9:  command <= 16'h1711; // HSTART
            8'd10: command <= 16'h1861; // HSTOP
            8'd11: command <= 16'h32A4; // HREF
            8'd12: command <= 16'h1903; // VSTART
            8'd13: command <= 16'h1A7b; // VSTOP
            8'd14: command <= 16'h030a; // VREF

            // 화질 및 색상 관련 표준 값들
            8'd15: command <= 16'h3dc0; // COM13
            8'd16: command <= 16'h1438; // COM9
            8'd17: command <= 16'h4f40; // MTX1
            8'd18: command <= 16'h5034; // MTX2
            8'd19: command <= 16'h510c; // MTX3
            8'd20: command <= 16'h5217; // MTX4
            8'd21: command <= 16'h5329; // MTX5
            8'd22: command <= 16'h5440; // MTX6
            8'd23: command <= 16'h581e; // MTXS
            8'd24: command <= 16'h1e20; // MVFP Flip/Mirror (필요시 0x00으로 변경)
            8'd25: command <= 16'h3c78; // COM12
            8'd26: command <= 16'h6900; // GFIX
            8'd27: command <= 16'hb084;
            8'd28: command <= 16'h0e61; // COM5
            8'd29: command <= 16'h0f4b;
            8'd30: command <= 16'h1602;
            8'd31: command <= 16'h2102;
            8'd32: command <= 16'h2291;
            8'd33: command <= 16'h2907;
            8'd34: command <= 16'h330b;
            8'd35: command <= 16'h350b;
            8'd36: command <= 16'h371d;
            8'd37: command <= 16'h392a;
            8'd38: command <= 16'h4d40;
            8'd39: command <= 16'h4e20;
            8'd40: command <= 16'h6b4a;
            8'd41: command <= 16'h7410;
            8'd42: command <= 16'h8d4f;
            8'd43: command <= 16'h8e00;
            8'd44: command <= 16'h8f00;
            8'd45: command <= 16'h9000;
            8'd46: command <= 16'h9100;
            8'd47: command <= 16'h9600;
            8'd48: command <= 16'h9a00;
            8'd49: command <= 16'hb10c;
            8'd50: command <= 16'hb20e;
            8'd51: command <= 16'hb382;
            8'd52: command <= 16'hb80a;
            8'd53: command <= 16'h13c7; // AGC/AEC - ON
            8'd54: command <= 16'h3871;
            8'd55: command <= 16'hFFFF; // 종료 신호
            default: command <= 16'hFFFF;
        endcase
    end
endmodule