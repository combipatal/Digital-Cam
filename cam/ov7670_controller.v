// OV7670 Controller Module
module ov7670_controller (
    input  wire       clk,
    input  wire       resend,
    output wire       config_finished,
    output wire       sioc,
    inout  wire       siod,
    output wire       reset,
    output wire       pwdn,
    output wire       xclk
);

    reg sys_clk = 1'b0;
    wire [15:0] command;
    wire finished;
    wire taken;
    wire send;
    
    parameter CAMERA_ADDR = 8'h42;  // Device write ID
    
    assign config_finished = finished;
    assign send = ~finished;
    assign reset = 1'b1;  // Normal mode
    assign pwdn = 1'b0;   // Power up
    assign xclk = sys_clk;
    
    // Generate camera clock (25MHz from 50MHz)
    always @(posedge clk) begin
        sys_clk <= ~sys_clk;
    end
    
    // I2C sender instance
    i2c_sender i2c_inst (
        .clk(clk),
        .taken(taken),
        .siod(siod),
        .sioc(sioc),
        .send(send),
        .id(CAMERA_ADDR),
        .data(command[15:8]),
        .value(command[7:0])
    );
    
    // Register configuration instance
    ov7670_registers reg_inst (
        .clk(clk),
        .advance(taken),
        .command(command),
        .finished(finished),
        .resend(resend)
    );
    
endmodule

// I2C Sender Module
module i2c_sender (
    input  wire       clk,
    inout  wire       siod,
    output reg        sioc,
    output reg        taken,
    input  wire       send,
    input  wire [7:0] id,
    input  wire [7:0] data,
    input  wire [7:0] value
);

    reg [7:0]  divider = 8'h01;
    reg [31:0] busy_sr = 32'h0;
    reg [31:0] data_sr = 32'hFFFFFFFF;
    
    // Tristate control for siod
    assign siod = ((busy_sr[11:10] == 2'b10) || 
                   (busy_sr[20:19] == 2'b10) || 
                   (busy_sr[29:28] == 2'b10)) ? 1'bZ : data_sr[31];
    
    always @(posedge clk) begin
        taken <= 1'b0;
        
        if (busy_sr[31] == 1'b0) begin
            sioc <= 1'b1;
            if (send == 1'b1) begin
                if (divider == 8'h00) begin
                    data_sr <= {3'b100, id, 1'b0, data, 1'b0, value, 1'b0, 2'b01};
                    busy_sr <= {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11};
                    taken <= 1'b1;
                end else begin
                    divider <= divider + 1'b1;
                end
            end
        end else begin
            // I2C timing state machine
            case ({busy_sr[31:29], busy_sr[2:0]})
                6'b111_111: sioc <= 1'b1;  // Start seq #1
                6'b111_110: sioc <= 1'b1;  // Start seq #2
                6'b111_100: sioc <= 1'b0;  // Start seq #3
                6'b110_000: sioc <= (divider[7:6] == 2'b00) ? 1'b0 : 1'b1;  // End seq #1
                6'b100_000: sioc <= 1'b1;  // End seq #2
                6'b000_000: sioc <= 1'b1;  // Idle
                default: sioc <= (divider[7:6] == 2'b00) ? 1'b0 : 
                                (divider[7:6] == 2'b11) ? 1'b0 : 1'b1;
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
    
endmodule

// OV7670 Register Configuration Module
module ov7670_registers (
    input  wire        clk,
    input  wire        resend,
    input  wire        advance,
    output reg  [15:0] command,
    output wire        finished
);

    reg [7:0] address = 8'h00;
    
    assign finished = (command == 16'hFFFF);
    
    always @(posedge clk) begin
        if (resend) begin
            address <= 8'h00;
        end else if (advance) begin
            address <= address + 1'b1;
        end
        
        // Register configuration sequence
        case (address)
            8'h00: command <= 16'h1280; // COM7 Reset
            
            // --- [추가] 화이트 밸런스 수동 설정 (붉은기 감소) ---
            8'h01: command <= 16'h0180; // BLUE: 파란색 채널 게인 (기본)
            8'h02: command <= 16'h0260; // RED:  빨간색 채널 게인 (낮춤)
            8'h03: command <= 16'h13E7; // COM8: AWB 비활성화, AGC/AEC 활성화
            // --- 화이트 밸런스 설정 끝 ---
            
            8'h04: command <= 16'h1204; // COM7: Size & RGB output
            8'h05: command <= 16'h1100; // CLKRC: Prescaler
            8'h06: command <= 16'h0C00; // COM3
            8'h07: command <= 16'h3E00; // COM14
            8'h08: command <= 16'h0400; // COM1
            8'h09: command <= 16'h4010; // COM15: RGB 565
            8'h0A: command <= 16'h3A04; // TSLB
            8'h0B: command <= 16'h1438; // COM9
            
            // --- [수정] 색상 매트릭스 값을 원래대로 조정 ---
            8'h0C: command <= 16'h4F40; // MTX1 (기존 0x80 -> 0x40)
            8'h0D: command <= 16'h5034; // MTX2
            8'h0E: command <= 16'h510C; // MTX3
            8'h0F: command <= 16'h5217; // MTX4
            8'h10: command <= 16'h5329; // MTX5
            8'h11: command <= 16'h5440; // MTX6 (기존 0x80 -> 0x40)
            
            8'h12: command <= 16'h581E; // MTXS
            8'h13: command <= 16'h3DC0; // COM13
            8'h14: command <= 16'h1711; // HSTART
            8'h15: command <= 16'h1861; // HSTOP
            8'h16: command <= 16'h32A4; // HREF
            8'h17: command <= 16'h1903; // VSTART
            8'h18: command <= 16'h1A7B; // VSTOP
            8'h19: command <= 16'h030A; // VREF
            8'h1A: command <= 16'h0E61; // COM5
            8'h1B: command <= 16'h0F4B; // COM6
            8'h1C: command <= 16'h1602;
            8'h1D: command <= 16'h1E37; // MVFP - Mirror/Flip
            8'h1E: command <= 16'h2102;
            8'h1F: command <= 16'h2291;
            8'h20: command <= 16'h2907;
            8'h21: command <= 16'h330B;
            8'h22: command <= 16'h350B;
            8'h23: command <= 16'h371D;
            8'h24: command <= 16'h3871;
            8'h25: command <= 16'h392A;
            8'h26: command <= 16'h3C78; // COM12
            8'h27: command <= 16'h4D40;
            8'h28: command <= 16'h4E20;
            8'h29: command <= 16'h6900; // GFIX
            8'h2A: command <= 16'h6B4A;
            8'h2B: command <= 16'h7410;
            8'h2C: command <= 16'h8D4F;
            8'h2D: command <= 16'h8E00;
            8'h2E: command <= 16'h8F00;
            8'h2F: command <= 16'h9000;
            8'h30: command <= 16'h9100;
            8'h31: command <= 16'h9600;
            8'h32: command <= 16'h9A00;
            8'h33: command <= 16'hB084;
            8'h34: command <= 16'hB10C;
            8'h35: command <= 16'hB20E;
            8'h36: command <= 16'hB382;
            8'h37: command <= 16'hB80A;
            8'h38: command <= 16'h5640; // CONTRAS
			8'h39: command <= 16'h5510; // BRIGHT (기본값 0x00)
            default: command <= 16'hFFFF;
        endcase
    end
endmodule