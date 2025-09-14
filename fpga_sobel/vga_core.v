`timescale 1ns / 1ps

module vga_core(
	input wire clk,rst_n, //clock must be 25MHz for 640x480 60fps
	output wire hsync,vsync,
	output reg video_on,
	output wire[11:0] pixel_x,pixel_y
    );		//640x480 @ 60fps parameters
	 localparam HM=799, //Horizontal Maximum (800 total - 1) for 640x480@60Hz
					HD=640, //Horizontal Display (640 pixels)
					HF=16,  //Horizontal Front Porch (a: 3.8us -> ~16 pixels)
					HR=96,  //Horizontal Retrace (b: 1.9us -> ~96 pixels)
					HB=48,  //Horizontal Back Porch (d: 0.6us -> ~48 pixels)
					
					VM=524, //Vertical Maximum (525 total - 1) for 640x480@60Hz
					VD=480, //Vertical Display (480 lines)
					VF=10,  //Vertical Front Porch (a: 2 lines -> 10 lines)
					VR=2,   //Vertical Retrace (b: 33 lines -> 2 lines)
					VB=33;  //Vertical Back Porch (d: 10 lines -> 33 lines)
	reg[11:0] vctr_q=0,vctr_d; //counter for vertical scan
	reg[11:0] hctr_q=0,hctr_d; //counter for vertical scan
	reg hsync_q=0,hsync_d;
	reg vsync_q=0,vsync_d;
	//vctr and hctr register operation
	always @(posedge clk,negedge rst_n) begin
		if(!rst_n) begin
			vctr_q<=0;
			hctr_q<=0;
			vsync_q<=0;
			hsync_q<=0;
		end
		else begin
			vctr_q<=vctr_d;
			hctr_q<=hctr_d;
			vsync_q<=vsync_d;
			hsync_q<=hsync_d;
		end
	end
	
	always @* begin
		vctr_d=vctr_q;
		hctr_d=hctr_q;
		video_on=0;
		hsync_d=1; 
		vsync_d=1; 
		
		// VHDL과 동일한 카운터 로직
		if(hctr_q == HM) begin // 799
			hctr_d = 0;
			if(vctr_q == VM) begin // 524
				vctr_d = 0;
			end else begin
				vctr_d = vctr_q + 1'b1;
			end
		end else begin
			hctr_d = hctr_q + 1'b1;
		end
		
		// video_on 신호 생성 (VHDL과 동일)
		if((hctr_q < HD) && (vctr_q < VD)) video_on = 1;
		
		// 동기 신호 생성 (VHDL과 동일한 타이밍)
		if((hctr_q >= (HD+HF)) && (hctr_q <= (HD+HF+HR-1))) hsync_d = 0; // Hcnt >= 656 and Hcnt <= 751
		if((vctr_q >= (VD+VF)) && (vctr_q <= (VD+VF+VR-1))) vsync_d = 0; // Vcnt >= 490 and Vcnt <= 491
	end
		assign vsync=vsync_q;
		assign hsync=hsync_q;
		assign pixel_x=hctr_q;
		assign pixel_y=vctr_q;

endmodule
