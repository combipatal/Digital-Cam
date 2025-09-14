`timescale 1ns / 1ps

module camera_interface(
    input wire clk, rst_n, // Main clock (50MHz)
    input wire[3:0] key,
    input wire resend_config, // Switch to reinitialize camera registers
    // Camera FIFO IO
    input wire rd_en,
    input wire rdclk,
    output wire[15:0] dout,
    output wire empty,
    output wire[15:0] data_count, // Output the number of words in FIFO (16-bit for 64K FIFO)
    // Camera pinouts
    input wire cmos_pclk, cmos_href, cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda, cmos_scl, // I2C/SCCB comm wires
    output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
    // Debugging
    output wire[3:0] led
);
    // FSM state declarations
    localparam    idle=0,
                  resend_wait=1,
                  start_sccb=2,
                  write_address=3,
                  write_data=4,
                  digest_loop=5,
                  delay=6,
                  vsync_fedge=7,
                  byte1=8,
                  byte2=8,
                  fifo_write=9;

    localparam MSG_INDEX=55; // OV7670 레지스터 개수

    reg[3:0] state_q=idle, state_d;
    reg[7:0] wr_data;
    reg start, stop;

    reg[3:0] led_q=0, led_d; 
    reg[27:0] delay_q=0, delay_d;
    reg start_delay_q=0, start_delay_d;
    reg delay_finish;
    reg[27:0] timeout_q=0, timeout_d;
    reg[15:0] message[MSG_INDEX:0];
    reg[7:0] message_index_q=0, message_index_d;
    reg[15:0] pixel_q, pixel_d;
    reg wr_en;
    
    wire rd_tick;
    wire[1:0] ack;
    wire[7:0] rd_data;
    wire[3:0] state;
    wire full;
    
    // PCLK-domain capture signals
    reg [7:0] byte_buf;
    reg byte_phase;
    wire [15:0] pixel_assembled;
    reg wrreq_camera;

    // Buffer for all inputs coming from the camera for synchronization (SCCB FSM only)
    reg pclk_1, pclk_2, href_1, href_2, vsync_1, vsync_2;

    initial begin
        // OV7670 레지스터 설정값 (RGB565 출력 모드)
        message[0]  = 16'h12_80; // COM7   Reset
        message[1]  = 16'h12_80; // COM7   Reset (두 번)
        message[2]  = 16'h12_14; // COM7   QVGA + RGB output
        message[3]  = 16'h11_80; // CLKRC  Use external clock directly
        message[4]  = 16'h0C_00; // COM3   Lots of stuff, enable scaling, all others off
        message[5]  = 16'h3E_00; // COM14  PCLK scaling off
        message[6]  = 16'h8C_00; // RGB444 Set RGB format
        message[7]  = 16'h04_00; // COM1   no CCIR601
        message[8]  = 16'h40_10; // COM15  Full 0-255 output, RGB 565
        message[9]  = 16'h3A_04; // TSLB   Set UV ordering,  do not auto-reset window
        message[10] = 16'h14_18; // COM9  - AGC Celling
        message[11] = 16'h4F_B3; // MTX1  - colour conversion matrix
        message[12] = 16'h50_B3; // MTX2  - colour conversion matrix
        message[13] = 16'h51_00; // MTX3  - colour conversion matrix
        message[14] = 16'h52_3D; // MTX4  - colour conversion matrix
        message[15] = 16'h53_A7; // MTX5  - colour conversion matrix
        message[16] = 16'h54_E4; // MTX6  - colour conversion matrix
        message[17] = 16'h58_9E; // MTXS  - Matrix sign and auto contrast
        message[18] = 16'h3D_C0; // COM13 - Turn on GAMMA and UV Auto adjust
        message[19] = 16'h11_80; // CLKRC  Use external clock directly
        message[20] = 16'h17_11; // HSTART HREF start (high 8 bits)
        message[21] = 16'h18_61; // HSTOP  HREF stop (high 8 bits)
        message[22] = 16'h32_A4; // HREF   Edge offset and low 3 bits of HSTART and HSTOP
        message[23] = 16'h19_03; // VSTART VSYNC start (high 8 bits)
        message[24] = 16'h1A_7B; // VSTOP  VSYNC stop (high 8 bits) 
        message[25] = 16'h03_0A; // VREF   VSYNC low two bits
        message[26] = 16'h0E_61; // COM5
        message[27] = 16'h0F_4B; // COM6
        message[28] = 16'h16_02; //
        message[29] = 16'h1E_07; // MVFP - 미러/플립 없음
        message[30] = 16'h21_02; //
        message[31] = 16'h22_91; //
        message[32] = 16'h29_07; //
        message[33] = 16'h33_0B; //
        message[34] = 16'h35_0B; //
        message[35] = 16'h37_1D; //
        message[36] = 16'h38_71; //
        message[37] = 16'h39_2A; //
        message[38] = 16'h3C_78; // COM12
        message[39] = 16'h4D_40; //
        message[40] = 16'h4E_20; //
        message[41] = 16'h69_00; // GFIX
        message[42] = 16'h6B_4A; //
        message[43] = 16'h74_10; //
        message[44] = 16'h8D_4F; //
        message[45] = 16'h8E_00; //
        message[46] = 16'h8F_00; //
        message[47] = 16'h90_00; //
        message[48] = 16'h91_00; //
        message[49] = 16'h96_00; //
        message[50] = 16'h9A_00; //
        message[51] = 16'hB0_84; //
        message[52] = 16'hB1_0C; //
        message[53] = 16'hB2_0E; //
        message[54] = 16'hB3_82; //
        message[55] = 16'hB8_0A; //
    end
     
    // Register operations
    always @(posedge clk, negedge rst_n) begin
        if(!rst_n) begin
            state_q <= idle;
            led_q <= 0;
            delay_q <= 0;
            start_delay_q <= 0;
            message_index_q <= 0;
            pixel_q <= 0;
            timeout_q <= 0;
            pclk_1 <= 0; pclk_2 <= 0;
            href_1 <= 0; href_2 <= 0;
            vsync_1 <= 0; vsync_2 <= 0;
        end
        else begin
            state_q <= state_d;
            led_q <= led_d;
            delay_q <= delay_d;
            start_delay_q <= start_delay_d;
            message_index_q <= message_index_d;         
            pixel_q <= pixel_d;
            timeout_q <= timeout_d;
            
            // Synchronize camera signals to system clock domain
            pclk_1 <= cmos_pclk; pclk_2 <= pclk_1;
            href_1 <= cmos_href; href_2 <= href_1;
            vsync_1 <= cmos_vsync; vsync_2 <= vsync_1;
        end
    end
         
    // FSM next-state logic
    always @* begin
        state_d = state_q;
        led_d = led_q;
        start = 0;
        stop = 0;
        wr_data = 0;
        start_delay_d = start_delay_q;
        delay_d = delay_q;
        delay_finish = 0;
        message_index_d = message_index_q;
        pixel_d = pixel_q;
        wr_en = 0;
        timeout_d = timeout_q + 1; 
        
        // Delay logic for SCCB timing
        if(start_delay_q) delay_d = delay_q + 1'b1;
        if(delay_q > 2500000) begin // ~50ms delay for SCCB stability
            delay_finish = 1;
            start_delay_d = 0;
            delay_d = 0;
        end
        
        case(state_q) 
            idle: begin
                led_d = 4'b0001; // 카메라 초기화 중
                if(resend_config) begin
                    state_d = resend_wait;
                    led_d = 4'b1010; // 재전송 대기
                    message_index_d = 0;
                    start_delay_d = 0;
                    delay_d = 0;
                end else begin
                    start_delay_d = 1;
                    if(delay_finish) begin
                        state_d = start_sccb; 
                        led_d = 4'b0010; // SCCB 시작
                        timeout_d = 0;
                    end
                end
            end
            
            resend_wait: begin
                led_d = 4'b1010; 
                start_delay_d = 1;
                if(delay_finish) begin
                    state_d = start_sccb; 
                    led_d = 4'b0010;
                end
            end
            
            start_sccb: begin
                led_d = 4'b0010; // SCCB 통신 시작
                start = 1;
                wr_data = 8'h42; // OV7670 write address
                state_d = write_address;
                timeout_d = 0;
            end
            
            write_address: begin
                if(ack[1] && ack[0]) begin
                    wr_data = message[message_index_q][15:8]; // 레지스터 주소
                    state_d = write_data;
                    led_d = 4'b0011; // 주소 쓰기 성공
                    timeout_d = 0;
                end
                else if(ack[1] && !ack[0]) begin // NACK 시 재시도
                    led_d = 4'b1010; 
                    state_d = start_sccb;
                    timeout_d = 0;
                end
                else if(timeout_q > 2500000) begin // 50ms 타임아웃
                    led_d = 4'b1110; // 타임아웃 오류
                    state_d = start_sccb;
                    timeout_d = 0;
                end
            end
            
            write_data: begin
                if(ack[1] && ack[0]) begin
                    wr_data = message[message_index_q][7:0]; // 데이터
                    state_d = digest_loop;
                    led_d = 4'b0100; // 데이터 쓰기 성공
                end
                else if(ack[1] && !ack[0]) begin 
                    led_d = 4'b1011;
                    state_d = start_sccb;
                end
                else if(timeout_q > 2500000) begin 
                    led_d = 4'b1110; 
                    state_d = start_sccb;
                    timeout_d = 0;
                end
            end
            
            digest_loop: begin
                if(ack[1] && ack[0]) begin
                    stop = 1;
                    start_delay_d = 1;
                    message_index_d = message_index_q + 1'b1;
                    state_d = delay;
                end
                else if(ack[1] && !ack[0]) begin 
                    state_d = start_sccb;
                end
                else if(timeout_q > 2500000) begin 
                    led_d = 4'b1110; 
                    state_d = start_sccb;
                    timeout_d = 0;
                end
            end
            
            delay: begin
                if(delay_finish) begin
                    if(message_index_q > MSG_INDEX) begin
                        state_d = vsync_fedge;
                        led_d = 4'b0101; // SCCB 설정 완료
                        timeout_d = 0;
                    end
                    else begin
                        state_d = start_sccb; 
                        led_d = 4'b0010; 
                    end
                end
            end
              
            vsync_fedge: begin
                led_d = 4'b0110; // VSYNC 대기
                // VSYNC 하강 에지 감지 (새 프레임 시작)
                if(!vsync_1 && vsync_2) begin 
                    state_d = byte1;
                    led_d = 4'b0111; // VSYNC 감지됨
                    timeout_d = 0;
                end
                // 디버깅: VSYNC 신호가 없으면 타임아웃 후 재초기화
                if(timeout_q > 50_000_000) begin // 1초 후 타임아웃
                    state_d = idle; 
                    led_d = 4'b1111; // 오류 상태
                    timeout_d = 0;
                end
            end
            
            byte1: begin
                led_d = 4'b1000; // 픽셀 캡처 시작
                // PCLK 도메인에서 실제 캡처가 이루어지므로 여기서는 대기
                // FIFO에 충분한 데이터가 있으면 성공으로 간주
                if(data_count > 1000) begin // 충분한 데이터 축적
                    led_d = 4'b0000; // 카메라 정상 동작
                    // 계속 캡처 상태 유지
                end else if(timeout_q > 100_000_000) begin // 2초 후 타임아웃
                    state_d = idle; // 재초기화
                    led_d = 4'b1111; // 오류 상태
                    timeout_d = 0;
                end
            end
            default: state_d = idle;
        endcase
    end
     
    assign cmos_pwdn = 0;  // Power device up
    assign cmos_rst_n = 1; // Normal mode
    assign led = led_q;
     
    // Module Instantiations
    i2c_top #(.freq(50_000)) i2c_sccb_controller ( // 50kHz for better compatibility
        .clk(clk), .rst_n(rst_n),
        .start(start), .stop(stop),
        .wr_data(wr_data),
        .rd_tick(rd_tick),
        .ack(ack),
        .rd_data(rd_data), 
        .scl(cmos_scl), .sda(cmos_sda),
        .state(state)
    ); 
     
    // PLL to generate 24MHz clock for the camera
    pll_24MHz camera_xclk_pll (
        .inclk0(clk),
        .c0(cmos_xclk),
        .areset(~rst_n),
        .locked()
    );
     
    // PCLK-domain pixel capture and FIFO write
    reg        latched_href, latched_vsync;
    reg [7:0]  latched_d;
    reg [15:0] d_latch; 
    reg [1:0]  line;    
    reg [6:0]  href_last; 
    reg [23:0] pclk_timeout; 
    reg byte_select; // 바이트 선택을 위한 토글

    // Latch camera signals on falling edge of PCLK
    always @(negedge cmos_pclk, negedge rst_n) begin
        if(!rst_n) begin
            latched_d     <= 8'd0;
            latched_href  <= 1'b0;
            latched_vsync <= 1'b0;
        end else begin
            latched_d     <= cmos_db;
            latched_href  <= cmos_href;
            latched_vsync <= cmos_vsync;
        end
    end

    // Assemble and write on rising edge of PCLK
    always @(posedge cmos_pclk, negedge rst_n) begin
        if(!rst_n) begin
            d_latch <= 16'd0;
            line <= 2'd0;
            href_last <= 7'd0;
            wrreq_camera <= 1'b0;
            pclk_timeout <= 0;
            byte_select <= 0;
        end else begin
            wrreq_camera <= 1'b0;
            pclk_timeout <= pclk_timeout + 1; 
            
            if(latched_vsync) begin
                // 새 프레임 시작 - 리셋 카운터들
                line <= 2'd0;
                href_last <= 7'd0;
                pclk_timeout <= 0;
                byte_select <= 0;
            end else begin
                // HREF 라이징 에지 감지 (새 스캔 라인 시작)
                if(href_last[0] == 1'b0 && latched_href == 1'b1) begin
                    line <= line + 1;
                    byte_select <= 0; // 새 라인마다 바이트 선택 리셋
                end
                
                // HREF 지연 업데이트
                href_last <= {href_last[5:0], latched_href};
                
                // 픽셀 데이터 캡처 (RGB565 모드)
                if(latched_href) begin
                    if(byte_select == 0) begin
                        d_latch[15:8] <= latched_d; // 첫 번째 바이트 (R+G 상위)
                        byte_select <= 1;
                    end else begin
                        d_latch[7:0] <= latched_d; // 두 번째 바이트 (G 하위+B)
                        byte_select <= 0;
                        // 두 번째 바이트가 오면 16비트 픽셀 완성
                        if(line >= 2'd2 && !full) begin // 몇 라인 스킵 후 캡처 시작
                            wrreq_camera <= 1'b1;
                        end
                    end
                end
                
                // 타임아웃 체크
                if(pclk_timeout > 24_000_000) begin // 약 1초 후 타임아웃
                    pclk_timeout <= 0; 
                end
            end
        end
    end
    
    // 픽셀 어셈블리 - RGB565 포맷 그대로 사용
    assign pixel_assembled = d_latch;
     
    // 64K Asynchronous FIFO to buffer pixel data
    asyn_fifo_large camera_fifo (
        .wrclk(cmos_pclk), // Write clock (PCLK)
        .rdclk(rdclk), // Read clock (main clock)
        .data(pixel_assembled),
        .wrreq(wrreq_camera),
        .rdreq(rd_en),
        .q(dout),
        .wrfull(full),
        .rdempty(empty),
        .wrusedw(),
        .rdusedw(data_count) // Output number of words in FIFO (read domain)
    );
    
endmodule