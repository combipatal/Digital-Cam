`timescale 1ns / 1ps

module vga_interface(
	input wire clk,rst_n,
	input wire sobel,
	input wire align_tick,
	//asyn_fifo IO
	input wire empty_fifo,
	input wire[16:0] din,
	//input wire clk_vga,
	output reg rd_en,
	input[7:0] threshold,
	//VGA output
	output reg[7:0] vga_r,
	output reg[7:0] vga_g,
	output reg[7:0] vga_b,
	output wire vga_hsync,
	output wire vga_vsync
);
	 //FSM state declarations
	 localparam delay=0,
					idle=1,
					display=2,
					align_frame=1,
					align_idle=0;
					
	 reg[1:0] state_q,state_d;
	 wire[11:0] pixel_x,pixel_y;
	 wire hsync,vsync,blank;
	 reg sobel_prev,state_align_q,state_align_d;
	 reg[4:0] align_count_q,align_count_d;
	 
	 //register operations
	 always @(posedge clk_vga,negedge rst_n) begin
		if(!rst_n) begin
			state_q<=delay;
			state_align_q<=align_idle;
			align_count_q<=0;
		end
		else begin
			state_q<=state_d;
			sobel_prev<=sobel;
			state_align_q<=state_align_d;
			align_count_q<=align_count_d;
		end
	 end
	 
	 //FSM next-state logic
	 always @* begin
		state_d=state_q;
		state_align_d=state_align_q;
		align_count_d=align_count_q;
		rd_en=0;
		vga_r=0;
		vga_g=0;
		vga_b=0;

		case(state_q)
			delay: if(blank) begin
					state_d=idle;
					state_align_d=align_frame;
				 end
			idle:  if(pixel_x==0 && pixel_y==0 && !empty_fifo) begin //wait for pixel-data coming from asyn_fifo 	
							if(sobel) begin
								vga_r=(din>threshold)? 8'hff:0;
								vga_g=(din>threshold)? 8'hff:0;
								vga_b=(din>threshold)? 8'hff:0;
							end
							else begin
								// 확장하여 RGB888로 변환
								vga_r={din[15:11], din[15:13]};
								vga_g={din[10:5], din[10:9]};
								vga_b={din[4:0], din[4:2]};
							end
							rd_en=1;	
							state_d=display;
					end
			display: if(!blank) begin //we will continue to read the asyn_fifo as long as current pixel coordinate is inside the visible screen(640x480) 
							 begin
								if(sobel) begin
									vga_r=(din>threshold)? 8'hff:0;
									vga_g=(din>threshold)? 8'hff:0;
									vga_b=(din>threshold)? 8'hff:0;
								end
								else begin
									// 확장하여 RGB888로 변환
									vga_r={din[15:11], din[15:13]};
									vga_g={din[10:5], din[10:9]};
									vga_b={din[4:0], din[4:2]};
								end
								rd_en=1;
							end
					end
			default: state_d=delay;
		endcase
		
		//automatically aligns frame when display changes (sobel-> rgb or rgb->sobel)
		case(state_align_q)
			 align_idle: if(sobel_prev != sobel) begin 
								state_align_d=align_frame;
								align_count_d=0;
						 end
			align_frame:  begin
							if(sobel && din[8] && din[15:9]==0 && rd_en) begin //align sobel frame 
								if(pixel_x==0 && pixel_y==0) begin 
									rd_en=1;
									align_count_d=align_count_q+1'b1;
									if(align_count_q==5) state_align_d=align_idle; //align for 5 frames
								end
								else rd_en=0;
							end
							else if(!sobel && din==16'b00000_000000_11111 && rd_en) begin //align rgb frame
								if(pixel_x==0 && pixel_y==0) begin 
									rd_en=1;
									align_count_d=align_count_q+1'b1;
									if(align_count_q==5) state_align_d=align_idle; //align for 5 frames
								end
								else rd_en=0;
							end
						  end
				default: state_align_d=align_idle;
		endcase
	 end

	// VGA 타이밍 제너레이터
	my_vga_clk_generator vga_gen
	(
		.pclk(clk_vga), 
		.out_hsync(hsync), 
		.out_vsync(vsync),
		.out_blank(blank),
		.out_hcnt(pixel_x),
		.out_vcnt(pixel_y),
		.reset_n(rst_n)
	);

	// VGA 출력 할당
	assign vga_hsync = hsync;
	assign vga_vsync = vsync;
endmodule