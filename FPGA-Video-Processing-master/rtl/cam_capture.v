// cam_capture.v (수정 완료)
module cam_capture
    (
    input  wire        i_pclk,     // 24 MHz; sourced from OV7670 camera
    input  wire        i_rstn,     // synchronous active low reset
    input  wire        i_cfg_done, // cam config done flag

    // OV7670 camera interface
    input  wire        i_vsync,    // active-high, indicates start of frame
    input  wire        i_hsync,    // [수정] href 대신 hsync 사용
    input  wire [7:0]  i_data,     // pixel data from camera

    // FIFO write interface
    output reg         o_wr,
    output reg  [11:0] o_wdata,    // fifo write data; {red, green, blue}

    output wire        o_sof       // start of frame flag
    );

    localparam H_ACTIVE = 320; // 실제 영상 가로 크기
    localparam V_ACTIVE = 240; // 실제 영상 세로 크기

    reg [9:0] h_count, nxt_h_count; // 수평 카운터
    reg [8:0] v_count, nxt_v_count; // 수직 카운터

    reg [11:0] nxt_wdata;
    reg [7:0]  byte1_data, nxt_byte1_data;
    reg        pixel_half, nxt_pixel_half;
    reg        nxt_wr;

    reg [1:0]  STATE, NEXT_STATE;
    localparam STATE_IDLE    = 0,
               STATE_ACTIVE  = 1,
               STATE_INITIAL = 2;

    wire is_active_area = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    
    // VSYNC와 HSYNC의 에지 감지
    reg vsync1, vsync2;
    assign o_sof = ((vsync1 == 0) && (vsync2 == 1)); // VSYNC 상승 에지 (Start of Frame)

    reg hsync1, hsync2;
    wire hsync_negedge = ((hsync1 == 1) && (hsync2 == 0)); // HSYNC 하강 에지 (Start of Line)

    always@(posedge i_pclk) begin
        if(!i_rstn) begin
            {vsync1, vsync2} <= 2'b0;
            {hsync1, hsync2} <= 2'b0;
        end
        else begin
            {vsync1, vsync2} <= {i_vsync, vsync1};
            {hsync1, hsync2} <= {i_hsync, hsync1};
        end
    end

    // FSM
    always@* begin
        nxt_wr         = 0;
        nxt_wdata      = o_wdata;
        nxt_byte1_data = byte1_data;
        nxt_pixel_half = pixel_half;
        nxt_h_count    = h_count;
        nxt_v_count    = v_count;
        NEXT_STATE     = STATE;

        case(STATE)
            STATE_INITIAL: begin
                NEXT_STATE = (i_cfg_done && o_sof) ? STATE_IDLE : STATE_INITIAL;
            end

            STATE_IDLE: begin
                nxt_wr         = 0;
                nxt_pixel_half = 1'b0; 
                nxt_h_count    = 0;
                nxt_v_count    = 0;
                NEXT_STATE = (o_sof) ? STATE_ACTIVE : STATE_IDLE;
            end

            STATE_ACTIVE: begin
                // [수정된 카운터 로직]
                if (hsync_negedge) begin
                    nxt_h_count = 0;
                    nxt_v_count = v_count + 1;
                end else begin
                    nxt_h_count = h_count + 1;
                end

                if (is_active_area) begin
                    nxt_pixel_half = ~pixel_half;
                    if (pixel_half) begin // 두 번째 바이트 (Green, Blue)
                        nxt_wr    = 1'b1;
                        nxt_wdata = {byte1_data[3:0], i_data};
                    end
                    else begin // 첫 번째 바이트 (Red)
                        nxt_wr              = 1'b0;
                        nxt_byte1_data[3:0] = i_data[3:0];
                    end
                end
                else begin
                    nxt_wr = 1'b0;
                end

                // 다음 프레임 시작 신호(o_sof)가 들어오면 IDLE 상태로 복귀
                NEXT_STATE = o_sof ? STATE_IDLE : STATE_ACTIVE;
            end
        endcase
    end

    always@(posedge i_pclk) begin
        if(!i_rstn) begin
            o_wr         <= 0;
            o_wdata      <= 0;
            byte1_data   <= 0;
            pixel_half   <= 0;
            h_count      <= 0;
            v_count      <= 0;
            STATE        <= STATE_INITIAL;
        end
        else begin
            o_wr         <= nxt_wr;
            o_wdata      <= nxt_wdata;
            byte1_data   <= nxt_byte1_data;
            pixel_half   <= nxt_pixel_half;
            h_count      <= nxt_h_count;
            v_count      <= nxt_v_count;
            STATE        <= NEXT_STATE;
        end
    end

endmodule