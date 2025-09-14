`timescale 1ns / 1ps

module sdram_interface(
	input clk,rst_n,
	//fifo for camera
	input wire clk_vga, rd_en,
	input wire sdram_clk_3ns,
	input wire sobel,
	input wire[9:0] data_count_camera_fifo, //number of data in camera fifo
	input wire[15:0] din, //data from camera fifo
	output reg rd_camera, //read camera fifo
	//fifo for vga
	output wire empty_fifo, 
	output wire[15:0] dout,
	//controller to sdram
	output wire sdram_clk,
	output wire sdram_cke, 
	output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, 
	output wire[12:0] sdram_addr,
	output wire[1:0] sdram_ba, 
	output wire[1:0] sdram_dqm, 
	inout[15:0] sdram_dq
    );
	 //FSM state declarations
	 localparam idle=0,
					write_camera=1,
					wait_write=2,
					read_for_vga=3,
					wait_read=4;
					
	 reg[2:0] state_q=0,state_d;	 
	 reg[14:0] wr_addr_q=0,wr_addr_d;  // 쓰기 주소
	 reg[14:0] rd_addr_q=0,rd_addr_d;  // 읽기 주소
	 reg rw,rw_en;
	 reg[14:0] f_addr;
	 reg[9:0] burst_count_q=0, burst_count_d;
	 
	 wire[15:0] s2f_data;
	 wire s2f_data_valid,f2s_data_valid;
	 wire ready;
	 wire[15:0] f2s_data;
	 wire[7:0] sobel_data;
	 
	 // VGA 요청 동기화 (VGA 25MHz -> SDRAM 133MHz)
	 reg rd_en_sync1, rd_en_sync2, rd_en_pulse;
	 reg empty_fifo_sync1, empty_fifo_sync2;
	 reg vga_needs_data;
	 
	 // 동기화 로직 - SDRAM 클럭 도메인에서 동작
	 always @(posedge clk, negedge rst_n) begin
		if (!rst_n) begin
			rd_en_sync1 <= 0;
			rd_en_sync2 <= 0;
			rd_en_pulse <= 0;
			empty_fifo_sync1 <= 1;
			empty_fifo_sync2 <= 1;
			vga_needs_data <= 0;
		end else begin
			// VGA read enable 동기화 및 edge detection (VGA 25MHz -> SDRAM 133MHz)
			rd_en_sync1 <= rd_en;
			rd_en_sync2 <= rd_en_sync1;
			rd_en_pulse <= rd_en_sync1 && !rd_en_sync2;
			
			// VGA FIFO empty 상태 동기화
			empty_fifo_sync1 <= empty_fifo;
			empty_fifo_sync2 <= empty_fifo_sync1;
			
			// VGA가 데이터를 필요로 하는지 감지 (더 간단한 조건)
			if (empty_fifo_sync2) begin
				vga_needs_data <= 1; // VGA FIFO가 비어있으면 데이터 필요
			end else if (s2f_data_valid) begin
				vga_needs_data <= 0; // 데이터가 도착하면 요청 해제
			end
		end
	 end
	 
	 //register operation
	 always @(posedge clk,negedge rst_n) begin
		if(!rst_n) begin
			state_q<=0;
			wr_addr_q<=0;
			rd_addr_q<=0;
			burst_count_q<=0;
			rd_camera<=0;
		end
		else begin
			state_q<=state_d;
			wr_addr_q<=wr_addr_d;
			rd_addr_q<=rd_addr_d;
			burst_count_q<=burst_count_d;
			
			// rd_camera는 SDRAM write burst 중에 활성화
			if(state_q == wait_write) begin
				rd_camera <= 1;
			end else begin
				rd_camera <= 0;
			end
		end
	 end
	 
	 //FSM next-state declarations
	 always @* begin
		state_d=state_q;
		wr_addr_d=wr_addr_q;
		rd_addr_d=rd_addr_q;
		burst_count_d=burst_count_q;
		f_addr=0;
		rw=0;
		rw_en=0;
		
		case(state_q)
			idle: begin
		// Priority 1: 카메라 데이터가 충분할 때 쓰기
		if(data_count_camera_fifo >= 10'd128 && ready) begin
			state_d = write_camera;
			rw_en = 1;
			rw = 0;  // write
			f_addr = wr_addr_q;
			burst_count_d = 0;
		end
				// Priority 2: VGA가 데이터를 요청할 때 읽기
				else if(vga_needs_data && ready) begin
					state_d = read_for_vga;
					rw_en = 1;
					rw = 1;  // read
					// sobel 모드에 따라 주소 결정
					f_addr = sobel ? (rd_addr_q + 1200) : rd_addr_q;  // 원본: 0-1199, sobel: 1200-2399
					burst_count_d = 0;
				end
			end
			
			write_camera: begin
				if(!ready) begin
					state_d = wait_write;
				end else begin
					state_d = idle;
					// 다음 쓰기 주소 계산 (640x480을 512word 단위로 분할)
					wr_addr_d = (wr_addr_q >= 1199) ? 0 : wr_addr_q + 1;
				end
			end
			
			wait_write: begin
				if(f2s_data_valid) begin
					burst_count_d = burst_count_q + 1;
				end
				if(ready) begin
					state_d = idle;
				end
			end
			
			read_for_vga: begin
				if(!ready) begin
					state_d = wait_read;
				end else begin
					state_d = idle;
					// 다음 읽기 주소
					rd_addr_d = (rd_addr_q >= 1199) ? 0 : rd_addr_q + 1;
				end
			end
			
			wait_read: begin
				if(ready) begin
					state_d = idle;
				end
			end
			
			default: state_d = idle;
		endcase
	 end
	 
	 // 데이터 선택 (원본 또는 sobel)
	 assign f2s_data = din;  // 현재는 원본만 저장 (sobel은 나중에 추가)
	 
	 //module instantiations
	 sdram_controller m0(
		//fpga to controller
		.clk(clk), //clk=133MHz (내부 로직용)
		.rst_n(rst_n),  
		.rw(rw), // 1:read , 0:write
		.rw_en(rw_en), //must be asserted before read/write
		.f_addr(f_addr), //14:2=row(13)  , 1:0=bank(2)
		.f2s_data(f2s_data), //fpga-to-sdram data
		.s2f_data(s2f_data), //sdram to fpga data
		.s2f_data_valid(s2f_data_valid),  
		.f2s_data_valid(f2s_data_valid), 
		.ready(ready), 
		//controller to sdram
		.s_clk(sdram_clk_3ns), 
		.s_cke(sdram_cke), 
		.s_cs_n(sdram_cs_n),
		.s_ras_n(sdram_ras_n ), 
		.s_cas_n(sdram_cas_n),
		.s_we_n(sdram_we_n), 
		.s_addr(sdram_addr), 
		.s_ba(sdram_ba), 
		.LDQM(sdram_dqm[0]),
		.HDQM(sdram_dqm[1]),
		.s_dq(sdram_dq)
		); 
	
	// VGA FIFO - SDRAM에서 읽은 데이터를 VGA 클럭 도메인으로 전달
	asyn_fifo m2 
	(
		.wrclk(clk),           // Write clock (133MHz SDRAM)
		.rdclk(clk_vga),       // Read clock (25MHz VGA)
		.data(s2f_data),       // Write data input
		.wrreq(s2f_data_valid), // Write request
		.rdreq(rd_en),         // Read request
		.q(dout),              // Read data output
		.wrfull(),             
		.rdempty(empty_fifo)   
    );
	
    // SDRAM 클럭 출력
    assign sdram_clk = sdram_clk_3ns;

endmodule