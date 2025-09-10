`timescale 1ns / 1ps

module vga_interface(
	input wire clk,rst_n,
	input wire sobel,
	//asyn_fifo IO
	input wire empty_fifo,
	input wire[15:0] din,
	output wire clk_vga,
	output reg rd_en,
	input[7:0] threshold,
	//VGA output
	output reg[4:0] vga_out_r,
	output reg[5:0] vga_out_g,
	output reg[4:0] vga_out_b,
	output wire vga_out_vs,vga_out_hs
    );
	 //FSM state declarations
	 localparam delay=0,
					idle=1,
					display=2;
					
	 reg[1:0] state_q,state_d;
	 wire[11:0] pixel_x,pixel_y;
	 wire video_on;
	 //register operations
	 always @(posedge clk_out,negedge rst_n) begin
		if(!rst_n) begin
			state_q<=delay;
		end
		else begin
			state_q<=state_d;
		end
	 end
	 
	 //FSM next-state logic
	 always @* begin
    state_d = state_q;
    rd_en = 0;
    vga_out_r = 0;
    vga_out_g = 0;
    vga_out_b = 0;
    
    case(state_q)
        delay:
            if(pixel_x == 1 && pixel_y == 1)
                state_d = idle;
        idle:
            if(!empty_fifo) begin // FIFO가 비어있지 않으면 바로 display 상태로
                state_d = display;
            end
        display: begin
            if(video_on && !empty_fifo) begin // video_on은 vga_core에서 받아와야 합니다.
                if(sobel) begin
                    // ... (소벨 로직)
                end
                else begin
                    vga_out_r = din[15:11];
                    vga_out_g = din[10:5];
                    vga_out_b = din[4:0];
                end
                rd_en = 1; // FIFO에서 데이터 읽기 요청
            end
            
            // 한 프레임이 끝나면 다시 delay 상태로 가서 다음 프레임을 기다립니다.
            if(pixel_x == 800-1 && pixel_y == 525-1) // vga_core의 전체 프레임 크기에 맞춰야 함
                state_d = delay;
        end
    endcase
end
	 
	assign clk_vga=clk_out;
	
	//module instantiations
	vga_core m0
	(
		.clk(clk_out), //clock must be 25MHz for 640x480
		.rst_n(rst_n),  
		.hsync(vga_out_hs),
		.vsync(vga_out_vs),
		.video_on(video_on),
		.pixel_x(pixel_x),
		.pixel_y(pixel_y)
	);	
	 PLL_25MHz m1 //clock for vga(620x480 60fps) 
   (// Clock in ports
    .inclk0(clk),      // IN
    // Clock out ports
    .c0(clk_out),     // OUT
    // Status and control signals
    .areset(RESET),// IN
    .locked(LOCKED));      // OUT
	 


endmodule
