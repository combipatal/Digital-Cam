module top_module(
	input wire clk,rst_n,
	input wire[3:0] key, //key[1:0] for threshold control, key[2] for switching display(RGB/Edge Detector)
	//camera pinouts
	input wire cmos_pclk,cmos_href,cmos_vsync,
	input wire[7:0] cmos_db,
	inout cmos_sda,cmos_scl, 
	output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
	//Debugging
	output[7:0] led, 
	//controller to sdram
	output wire sdram_clk,
	output wire sdram_cke, 
	output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, 
	output wire[12:0] sdram_addr,
	output wire[1:0] sdram_ba, 
	output wire[1:0] sdram_dqm, 
	inout[15:0] sdram_dq,
	//VGA output
	output wire[7:0] vga_r,
	output wire[7:0] vga_g,
	output wire[7:0] vga_b,
	output wire vga_hsync,
	output wire vga_vsync
);
	 
	wire f2s_data_valid;
	wire[10:0] data_count_r,data_count_r_sobel;
	wire[16:0] dout,din;
	wire clk_sdram;
	wire empty_fifo,empty;
	wire clk_vga;
	wire state;
	wire rd_sobel;
	wire rd_en,rd_fifo;
	wire[8:0] sobel_data;
	wire[9:0] data_count_sobel;
	wire rd_en_sobel;
	wire[16:0] dout_sobel;
	reg[7:0] threshold=0;
	reg sobel=0;
	
	//register operation 
	always @(posedge clk) begin
		if(!rst_n) begin
			threshold=0;
			sobel<=0;
		end
		else begin
			threshold=key1_tick? threshold+1:threshold;  //decrease sensitivity of sobel edge detection
			threshold=key2_tick? threshold-1:threshold;	//increase sensitivity of sobel edge detection
			sobel<=key3_tick? !sobel:sobel; //choose whether to display the raw video or the edge detected video
		end
	end
	
	//module instantiations
	camera_interface m0
	(
		.clk(clk),
		.clk_100(clk_sdram),
		.rst_n(rst_n),
		.key(),
		//sobel
		.rd_en_sobel(rd_en_sobel),
		.dout_sobel(dout_sobel),
		.data_count_r_sobel(data_count_r_sobel),
		//camera fifo IO
		.rd_en(rd_fifo),
		.data_count_r(data_count_r),
		.dout(dout),
		//camera pinouts
		.cmos_pclk(cmos_pclk),
		.cmos_href(cmos_href),
		.cmos_vsync(cmos_vsync),
		.cmos_db(cmos_db),
		.cmos_sda(cmos_sda),
		.cmos_scl(cmos_scl), 
		.cmos_rst_n(cmos_rst_n),
		.cmos_pwdn(cmos_pwdn),
		.cmos_xclk(cmos_xclk),
		//Debugging
		.led(led)
    );
	 
	sdram_interface m1
	(
		.clk(clk_sdram),
		.rst_n(rst_n),
		.clk_vga(clk_vga),
		.rd_en(rd_en),
		.sobel(sobel),
		//fifo for camera
		.data_count_camera_fifo(data_count_r),
		.din(dout),
		.rd_camera(rd_fifo),
		//sobel
		.sobel_data(sobel_data),
		.data_count_r(data_count_sobel),
		.rd_sobel(rd_sobel),
		//fifo for vga
		.empty_fifo(empty_fifo),
		.dout(din),
		//controller to sdram
		.sdram_clk(sdram_clk),
		.sdram_cke(sdram_cke), 
		.sdram_cs_n(sdram_cs_n),
		.sdram_ras_n(sdram_ras_n),
		.sdram_cas_n(sdram_cas_n),
		.sdram_we_n(sdram_we_n), 
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba), 
		.sdram_dqm(sdram_dqm),
		.sdram_dq(sdram_dq)
    );
	 
	vga_interface m2
	(
		.clk(clk_vga),
		.rst_n(rst_n),
		//.clk_vga(clk_vga),
		.sobel(sobel),
		.align_tick(key[3]),
		//asyn_fifo IO
		.empty_fifo(empty_fifo),
		.din(din),
		.rd_en(rd_en),
		.threshold(threshold),
		//VGA output
		.vga_r(vga_r),
		.vga_g(vga_g),
		.vga_b(vga_b),
		.vga_hsync(vga_hsync),
		.vga_vsync(vga_vsync)
    );
	
	sobel_convolution m3 
	(	
		.clk_w(clk),
		.clk_r(clk_sdram),
		.rst_n(rst_n),
		.din(dout_sobel),
		.data_count_r_sobel(data_count_r_sobel),
		.rd_fifo(rd_sobel), 
		.rd_fifo_cam(rd_en_sobel),
		.dout(sobel_data),
		.data_count_r(data_count_sobel)
    );
	 
	// PLL 인스턴스화는 필요하지 않음 (IP를 통해 추가 예정)
	// 필요한 클럭:
	// 1. clk_sdram (143MHz)
	// 2. clk_vga (25MHz)
	main_pll pll_clk
	(
		.inclk0(clk),
		.c0(clk_sdram),
		.c1(clk_vga),
		.c2(),
		.locked()
	);
	debounce_explicit m5
	(
		.clk(clk),
		.rst_n(rst_n),
		.sw({key[0]}),
		.db_level(),
		.db_tick(key1_tick)
    );
	 
	debounce_explicit m6
	(
		.clk(clk),
		.rst_n(rst_n),
		.sw({key[1]}),
		.db_level(),
		.db_tick(key2_tick)
    );
	 
	debounce_explicit m7
	(
		.clk(clk),
		.rst_n(rst_n),
		.sw({key[2]}),
		.db_level(),
		.db_tick(key3_tick)
    );
endmodule