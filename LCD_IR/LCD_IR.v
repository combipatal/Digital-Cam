module LCD_IR (
input clk,
input rst_n,
input IRDA_RXD,
input lcd_button,

output lcd_rs, 
output lcd_en,
output lcd_rw,
output lcd_out_on,
output [7:0]lcd_data,
output [6:0]seven_seg_out1,
output [6:0]seven_seg_out2
);

wire [7:0]         	captured_code;
reg [7:0]          	input_data;
reg  [1:0]          data_valid_save;
wire                data_valid;
reg                 data_valid_d;
wire                data_valid_pulse;
reg  [7:0]          captured_code_d;      // captured_code 1클록 지연
reg                 data_valid_pulse_d;   // 유효 펄스 1클록 지연
reg  [7:0]          seg_latched_code;     // 7세그 표시용 래치 값
reg                 data_valid_pulse_dd;  // 유효 펄스 2클록 지연 (LCD 트리거용)

// data_valid의 상승에지를 1클록 펄스로 만든 뒤 2비트 쉬프트로 전달
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_valid_save <= 2'b00;
    end else begin
        // LCD는 input_data 갱신 이후 한 클록 뒤에 트리거되도록 [1] 비트로 전달
        data_valid_save <= {data_valid_pulse_dd, 1'b0};
    end
end

LCD_1 U1(
	.lcd_data(lcd_data),                  		// lcd data
	.lcd_en(lcd_en),                        	// lcd enable
	.lcd_rw(lcd_rw),                            // lcd read/write (write = 0, read = 1)     
	.lcd_rs(lcd_rs),                         	// Command/Data Select (Command = 0,Data = 1)
	.lcd_out_on(lcd_out_on),                    // lcd power
	.input_data(input_data),                    // lcd input data
    					
	.data_valid(data_valid_save), 
	.clk(clk),
	.rst_n(rst_n),
	.lcd_in_on(lcd_button)                    // lcd power on in (button)
    );
	 
    
IR_RECEVER U2 (
    .clk(clk),          			// 50MHz 클럭 기준
    .rst_n(rst_n),
	.IRDA_RXD(IRDA_RXD),    		// IR 수신기 입력
	.captured_code(captured_code),  	// 최종 해독된 키 데이터 
	.data_valid(data_valid)
);



seven_segment_decoder U3 (
	.binary_in(seg_latched_code[3:0]),      // 4비트 2진수 입력 (0x0 ~ 0xF)
	.seven_seg_out(seven_seg_out1) // 7세그먼트 출력 (g,f,e,d,c,b,a)
);

seven_segment_decoder U4 (
	.binary_in(seg_latched_code[7:4]),      // 4비트 2진수 입력 (0x0 ~ 0xF)
	.seven_seg_out(seven_seg_out2) // 7세그먼트 출력 (g,f,e,d,c,b,a)
);




always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_data <= 8'h30; // 기본값 '0'
        data_valid_d <= 1'b0;
        captured_code_d <= 8'h00;
        data_valid_pulse_d <= 1'b0;
        data_valid_pulse_dd <= 1'b0;
        seg_latched_code <= 8'h00;
    end else begin
        // 동기화: 한 사이클 뒤에 값이 유효하도록 지연
        data_valid_d <= data_valid;
        captured_code_d <= captured_code;
        data_valid_pulse_d <= data_valid_pulse;
        data_valid_pulse_dd <= data_valid_pulse_d;

        // 새로운 키 수신 시에만 input_data 갱신 (지연된 코드 사용)
        if (data_valid_pulse_d) begin
            case (captured_code_d)
                8'h00: input_data <= 8'h30; // '0'
                8'h01: input_data <= 8'h31; // '1'
                8'h02: input_data <= 8'h32; // '2'
                8'h03: input_data <= 8'h33; // '3'
                8'h04: input_data <= 8'h34; // '4'
                8'h05: input_data <= 8'h35; // '5'
                8'h06: input_data <= 8'h36; // '6'
                8'h07: input_data <= 8'h37; // '7'
                8'h08: input_data <= 8'h38; // '8'
                8'h09: input_data <= 8'h39; // '9'
                8'h0F: input_data <= 8'h41; // 'A'
                8'h13: input_data <= 8'h42; // 'B'
                8'h10: input_data <= 8'h43; // 'C'
                default: input_data <= 8'h30; // 기본값 (예: '0')
            endcase
        end

        // 7세그는 data_valid 펄스가 발생한 같은 클록에서 최신 코드를 래치
        if (data_valid_pulse) begin
            seg_latched_code <= captured_code;
        end
    end
end

assign data_valid_pulse = data_valid & ~data_valid_d; // 상승에지 검출 1클록 펄스
endmodule