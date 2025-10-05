// OV7670 移대찓???명꽣?섏씠??理쒖긽??紐⑤뱢
// 移대찓??罹≪쿂, ?꾨젅??踰꾪띁, VGA ?붿뒪?뚮젅?대? ?듯빀??硫붿씤 紐⑤뱢
module digital_cam_top (
    input  wire        btn_thr_up,     // Sobel ?꾧퀎 利앷? 踰꾪듉 (?≫떚釉?濡쒖슦)
    input  wire        btn_thr_down,   // Sobel ?꾧퀎 媛먯냼 踰꾪듉 (?≫떚釉?濡쒖슦)
    input  wire        clk_50,         // 50MHz ?쒖뒪???대윮
    input  wire        btn_resend,     // 移대찓???ㅼ젙 ?ъ떆??踰꾪듉
    input  wire        sw_grayscale,   // SW[0] 洹몃젅?댁뒪耳??紐⑤뱶 ?ㅼ쐞移?
    input  wire        sw_sobel,       // SW[1] ?뚮꺼 ?꾪꽣 紐⑤뱶 ?ㅼ쐞移?
    input  wire        sw_filter,      // SW[2] ?붿????꾪꽣 紐⑤뱶 ?ㅼ쐞移?
    input  wire        sw_canny,       // SW[3] 罹먮땲 ?ｌ? 紐⑤뱶 ?ㅼ쐞移?
    output wire        led_config_finished,  // ?ㅼ젙 ?꾨즺 LED
    
    // VGA 異쒕젰 ?좏샇??
    output wire        vga_hsync,      // VGA ?섑룊 ?숆린??
    output wire        vga_vsync,      // VGA ?섏쭅 ?숆린??
    output wire [7:0]  vga_r,          // VGA 鍮④컙??(8鍮꾪듃)
    output wire [7:0]  vga_g,          // VGA 珥덈줉??(8鍮꾪듃)
    output wire [7:0]  vga_b,          // VGA ?뚮???(8鍮꾪듃)
    output wire        vga_blank_N,    // VGA 釉붾옲???좏샇
    output wire        vga_sync_N,     // VGA ?숆린???좏샇
    output wire        vga_CLK,        // VGA ?대윮
    
    // OV7670 移대찓???명꽣?섏씠??
    input  wire        ov7670_pclk,    // 移대찓???쎌? ?대윮
    output wire        ov7670_xclk,    // 移대찓???쒖뒪???대윮
    input  wire        ov7670_vsync,   // 移대찓???섏쭅 ?숆린??
    input  wire        ov7670_href,    // 移대찓???섑룊 李몄“
    input  wire [7:0]  ov7670_data,    // 移대찓???쎌? ?곗씠??
    output wire        ov7670_sioc,    // 移대찓??I2C ?대윮
    inout  wire        ov7670_siod,    // 移대찓??I2C ?곗씠??
    output wire        ov7670_pwdn,    // 移대찓???뚯썙?ㅼ슫
    output wire        ov7670_reset    // 移대찓??由ъ뀑
);

    // ?대? ?좏샇??
    wire clk_24_camera;  // 移대찓?쇱슜 24MHz ?대윮
    wire clk_25_vga;     // VGA??25MHz ?대윮
    wire wren;           // RAM ?곌린 ?쒖꽦??
    wire resend;         // 移대찓???ㅼ젙 ?ъ떆??
    wire [16:0] wraddress;  // RAM ?곌린 二쇱냼
    wire [15:0] wrdata;     // RAM ?곌린 ?곗씠??(RGB565)
    wire [16:0] rdaddress;  // RAM ?쎄린 二쇱냼
    wire [15:0] rddata;     // RAM ?쎄린 ?곗씠??(RGB565)
    wire activeArea;        // VGA ?쒖꽦 ?곸뿭

    // 罹≪쿂 珥덇린 吏??濡쒖쭅 - 泥??꾨젅???꾨즺 ??VGA ?쒖꽦??
    reg first_frame_captured = 1'b0;  // 泥??꾨젅??罹≪쿂 ?꾨즺 ?뚮옒洹?(pclk ?꾨찓??
    reg vsync_prev_pclk = 1'b0;       // vsync ?댁쟾 媛?(pclk ?꾨찓??
    
    // 泥??꾨젅???꾨즺 媛먯? (罹≪쿂 ?대윮 ?꾨찓??
    always @(posedge ov7670_pclk) begin
        vsync_prev_pclk <= ov7670_vsync;
        // vsync ?섍컯 ?먯? = ?꾨젅???꾨즺
        if (vsync_prev_pclk && !ov7670_vsync && !first_frame_captured) begin
            first_frame_captured <= 1'b1;
        end
        // 由ъ뀑 ??珥덇린??
        if (resend) begin
            first_frame_captured <= 1'b0;
        end
    end
    
    // CDC (Clock Domain Crossing) ?숆린?? pclk ??clk_25_vga
    reg frame_ready_sync1 = 1'b0;
    reg frame_ready_sync2 = 1'b0;
    always @(posedge clk_25_vga) begin
        frame_ready_sync1 <= first_frame_captured;
        frame_ready_sync2 <= frame_ready_sync1;  // 2???숆린??
    end
    
    wire vga_enable;  // VGA 異쒕젰 ?쒖꽦???좏샇

    // ????꾨젅??踰꾪띁 ?좏샇??(320x240 = 76800 ?쎌?????媛쒖쓽 RAM?쇰줈 遺꾪븷)
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16鍮꾪듃 二쇱냼 (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16鍮꾪듃 二쇱냼 (0-44031)
    wire [15:0] wrdata_ram1, wrdata_ram2;       // 媛?RAM???곌린 ?곗씠??(RGB565)
    wire wren_ram1, wren_ram2;                  // 媛?RAM???곌린 ?쒖꽦??
    wire [15:0] rddata_ram1, rddata_ram2;       // 媛?RAM???쎄린 ?곗씠??(RGB565)

    // 移대찓??由ъ뀑??踰꾪듉 ?붾컮?댁떛 (媛꾨떒 蹂듭썝: 20ms)
    reg [19:0] btn_counter = 20'd0;     // 踰꾪듉 移댁슫??(20ms ?붾컮?댁떛??
    reg btn_pressed = 1'b0;             // 踰꾪듉 ?뚮┝ ?곹깭
    reg btn_pressed_prev = 1'b0;        // ?댁쟾 踰꾪듉 ?곹깭
    wire btn_rising_edge;               // 踰꾪듉 ?곸듅 ?먯?

    always @(posedge clk_50) begin
        if (btn_resend == 1'b0) begin  // 踰꾪듉???뚮졇????(?≫떚釉?濡쒖슦)
            if (btn_counter < 20'd1000000)  // 20ms ?붾컮?댁떛 (50MHz?먯꽌)
                btn_counter <= btn_counter + 1'b1;
            else
                btn_pressed <= 1'b1;  // 踰꾪듉???덉젙?곸쑝濡??뚮┝
        end else begin
            btn_counter <= 20'd0;     // 移댁슫??由ъ뀑
            btn_pressed <= 1'b0;      // 踰꾪듉 ?곹깭 由ъ뀑
        end
        btn_pressed_prev <= btn_pressed;  // ?댁쟾 ?곹깭 ???
    end

    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;  // ?곸듅 ?먯? 媛먯?
    assign resend = btn_rising_edge;  // 踰꾪듉 ?곸듅 ?먯??먯꽌 由ъ뀑 ?꾩뒪 ?꾩넚

    // Sobel ?꾧퀎 利앷?/媛먯냼 踰꾪듉 ?붾컮?댁떛 (?≫떚釉?濡쒖슦, 20ms)
    reg [19:0] up_cnt   = 20'd0;
    reg [19:0] down_cnt = 20'd0;
    reg up_stable   = 1'b0, up_prev   = 1'b0;
    reg down_stable = 1'b0, down_prev = 1'b0;
    wire up_pulse, down_pulse;
    always @(posedge clk_50) begin
        // UP
        if (btn_thr_up == 1'b0) begin
            if (up_cnt < 20'd1000000) up_cnt <= up_cnt + 1'b1; else up_stable <= 1'b1;
        end else begin
            up_cnt <= 20'd0; up_stable <= 1'b0;
        end
        up_prev <= up_stable;
        // DOWN
        if (btn_thr_down == 1'b0) begin
            if (down_cnt < 20'd1000000) down_cnt <= down_cnt + 1'b1; else down_stable <= 1'b1;
        end else begin
            down_cnt <= 20'd0; down_stable <= 1'b0;
        end
        down_prev <= down_stable;
    end
    assign up_pulse   = up_stable & ~up_prev;
    assign down_pulse = down_stable & ~down_prev;

    // Sobel ?꾧퀎媛?(踰꾪듉 2/3濡?利앷컧)
    reg  [7:0] sobel_threshold_btn = 8'd64; // 珥덇린 64
    always @(posedge clk_50) begin
        if (up_pulse)   sobel_threshold_btn <= (sobel_threshold_btn >= 8'd250) ? 8'd255 : (sobel_threshold_btn + 8'd5);
        if (down_pulse) sobel_threshold_btn <= (sobel_threshold_btn <= 8'd5)   ? 8'd0   : (sobel_threshold_btn - 8'd5);
    end

    // ?곌린 二쇱냼 ?좊떦
    assign wraddress_ram1 = wraddress[15:0];  // RAM1: 0-32767 (16鍮꾪듃)
    wire [16:0] wraddr_sub = wraddress - 17'd32768;
    assign wraddress_ram2 = wraddr_sub[15:0];  // RAM2: 0-44031 (?뺤긽 ?ㅽ봽??
    assign wrdata_ram1 = wrdata;              // RAM1 ?곌린 ?곗씠??
    assign wrdata_ram2 = wrdata;              // RAM2 ?곌린 ?곗씠??
    assign wren_ram1 = wren & ~wraddress[16]; // 二쇱냼 < 32768????RAM1???곌린
    assign wren_ram2 = wren & wraddress[16];  // 二쇱냼 >= 32768????RAM2???곌린

    // ?쎄린 二쇱냼 ?좊떦
    // Read-side addresses must use the memory-aligned address (latency = MEM_RD_LAT)
    assign rdaddress_ram1 = rdaddress_aligned[15:0];  // RAM1: 0-32767 (16鍮꾪듃)
    wire [16:0] rdaddr_sub = rdaddress_aligned - 17'd32768;
    assign rdaddress_ram2 = rdaddr_sub[15:0];  // RAM2: 0-44031 (?뺤긽 ?ㅽ봽??

    // ?쎄린 ?곗씠??硫?고뵆?됱떛 - ?곸쐞 鍮꾪듃???곕씪 ?대뒓 RAM?먯꽌 ?쎌쓣吏 寃곗젙
    // 硫붾え由?異쒕젰(rddata)? 2?대윮 ?ㅼ쓽 二쇱냼???대떦?섎?濡? ?좏깮 ?좏샇???뺣젹??二쇱냼瑜??ъ슜
    assign rddata = rdaddress_aligned[16] ? rddata_ram2 : rddata_ram1;

    // RGB 蹂??諛?洹몃젅?댁뒪耳?? ?뚮꺼 ?꾪꽣, ?붿????꾪꽣 紐⑤뱶
    wire [7:0] gray_value;           // 洹몃젅?댁뒪耳??媛?
    wire [7:0] red_value, green_value, blue_value;  // RGB 媛믩뱾
    wire [7:0] sobel_value;          // ?뚮꺼 ?꾪꽣 媛?(洹몃젅?댁뒪耳??
    wire [7:0] canny_value;          // 罹먮땲 ?ｌ? 媛?(?댁쭊)
    wire [23:0] filtered_pixel;      // ?붿????꾪꽣 ?곸슜???쎌? (RGB888) - 洹몃젅??蹂듭젣
    wire filter_ready;               // ?꾪꽣 泥섎━ ?꾨즺 ?좏샇
    wire filter_ready2;              // 2李?媛?곗떆??ready
    wire sobel_ready;                // ?뚮꺼 泥섎━ ?꾨즺 ?좏샇 (?좎뼵???욌떦寃??ъ슜 ?댁쟾??諛곗튂)
    
    // RGB565 ??RGB888 吏곸젒 蹂??(?붿쭏 理쒖쟻??
    // RGB565: R[15:11] G[10:5] B[4:0]
    // RGB888: R[7:0] G[7:0] B[7:0]
    wire [7:0] r_888, g_888, b_888;  // RGB888濡??뺤옣??媛믩뱾
    
    assign r_888 = {rddata[15:11], 3'b111};  // 5鍮꾪듃 ??8鍮꾪듃 鍮꾪듃蹂듭젣
    assign g_888 = {rddata[10:5], 2'b11};   // 6鍮꾪듃 ??8鍮꾪듃 鍮꾪듃蹂듭젣
    assign b_888 = {rddata[4:0],  3'b11};    // 5鍮꾪듃 ??8鍮꾪듃 鍮꾪듃蹂듭젣
    
    // RGB888???섎굹??24鍮꾪듃 ?쎌?濡?寃고빀 (?꾪꽣 ?낅젰??
    wire [23:0] rgb888_pixel = {r_888, g_888, b_888};

    // VGA ?숆린???좏샇 ?먮낯 (?ъ슜 吏???댁쟾???좎뼵)
    wire hsync_raw, vsync_raw;
    wire vga_blank_N_raw;
    wire vga_sync_N_raw;

    // ?꾨젅??寃쎄퀎?먯꽌 VGA 異쒕젰 ?쒖꽦??(vsync ?곸듅 ?먯? ?댄썑)
    reg vga_enable_reg = 1'b0;
    reg vsync_prev_display = 1'b1;
    always @(posedge clk_25_vga) begin
        vsync_prev_display <= vsync_raw;
        if (!frame_ready_sync2) begin
            vga_enable_reg <= 1'b0;
        end else if (!vsync_prev_display && vsync_raw) begin
            vga_enable_reg <= 1'b1;
        end
    end
    assign vga_enable = vga_enable_reg;

    // 硫붾え由?Read) 吏??蹂댁젙: ??쇳룷??RAM B?ы듃??address_reg + outdata_reg濡?2?대윮 吏??
    localparam integer MEM_RD_LAT = 2;
    // ?쒖꽦?곸뿭/二쇱냼瑜?硫붾え由?異쒕젰(lat=2)???뺣젹
    reg        activeArea_d1 = 1'b0, activeArea_d2 = 1'b0;
    reg [16:0] rdaddress_d1 = 17'd0, rdaddress_d2 = 17'd0;
    // ?쇱씤 ?쒖옉 1?대윮 ?꾨━移댁슫?? active ?곸듅 吏곹썑 泥??쎌??먯꽌 二쇱냼瑜?1 ?욌떦寃?硫붾え由??붿껌
    wire       active_rise = activeArea && !activeArea_d1;
    wire [16:0] rdaddress_pre = (active_rise && (rdaddress != 17'd0)) ? (rdaddress - 17'd1) : rdaddress;
    always @(posedge clk_25_vga) begin
        activeArea_d1 <= activeArea;
        activeArea_d2 <= activeArea_d1;
        rdaddress_d1  <= rdaddress_pre;
        rdaddress_d2  <= rdaddress_d1;
    end
    wire        activeArea_aligned = activeArea_d2;     // 硫붾え由??곗씠??rddata)???뺣젹??active
    wire [16:0] rdaddress_aligned  = rdaddress_d2;      // 硫붾え由??곗씠??rddata)???뺣젹??二쇱냼

    // Sobel ?꾩슜 x/y 移댁슫???뺣젹??active 湲곗?) -> {y[7:0], x[8:0]}
    reg        active_aligned_prev = 1'b0;
    reg        vsync_prev_aligned  = 1'b1;
    reg [8:0]  sobel_x = 9'd0;     // 0..319
    reg [7:0]  sobel_y = 8'd0;     // 0..239
    always @(posedge clk_25_vga) begin
        vsync_prev_aligned  <= vsync_raw;
        active_aligned_prev <= activeArea_aligned;
        // ?꾨젅???쒖옉?먯꽌 y 由ъ뀑 (VSYNC ?곸듅 ?먯? 湲곗?)
        if (!vsync_prev_aligned && vsync_raw) begin
            sobel_y <= 8'd0;
        end
        // ?쇱씤 ?쒖옉?먯꽌 x 由ъ뀑
        if (activeArea_aligned && !active_aligned_prev) begin
            sobel_x <= 9'd0;
        end else if (activeArea_aligned) begin
            if (sobel_x < 9'd319) sobel_x <= sobel_x + 1'b1;
        end
        // ?쇱씤 醫낅즺?먯꽌 y 利앷?
        if (!activeArea_aligned && active_aligned_prev) begin
            if (sobel_y < 8'd239) sobel_y <= sobel_y + 1'b1;
        end
    end
    wire [16:0] sobel_addr_aligned = {sobel_y, sobel_x};

    // 洹몃젅?댁뒪耳??怨꾩궛
    wire [16:0] gray_sum;
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);
    assign gray_value = activeArea_aligned ? gray_sum[16:8] : 8'h00;

    // ?꾪꽣 ?곸슜???쎌??먯꽌 RGB 遺꾨━
    wire [7:0] filter_r_888, filter_g_888, filter_b_888;

    // ?뚯씠?꾨씪??吏?? 寃쎈줈蹂??곸씠
    // - 媛?곗떆??2?? 4?대윮, ?뚮꺼 異붽?: 2?대윮 ??珥?6?대윮
    // Gaussian pipeline latency (per gaussian_3x3_gray8): 2 clocks
    localparam integer GAUSS_LAT = 2;
    localparam integer SOBEL_EXTRA_LAT = 2;
    localparam integer PIPE_LATENCY = GAUSS_LAT * 2 + SOBEL_EXTRA_LAT; // 6
    reg [16:0] rdaddress_delayed [PIPE_LATENCY:0];      // rdaddress delayed value
    reg activeArea_delayed [PIPE_LATENCY:0];            // active area delayed value
    reg [7:0] red_value_delayed [PIPE_LATENCY:0];       // red delayed value
    reg [7:0] green_value_delayed [PIPE_LATENCY:0];     // green delayed value
    reg [7:0] blue_value_delayed [PIPE_LATENCY:0];      // blue delayed value
    reg [7:0] gray_value_delayed [PIPE_LATENCY:0];      // gray delayed value
    reg [23:0] filtered_pixel_delayed [PIPE_LATENCY:0]; // filtered pixel delayed value
    reg [7:0] filter_r_delayed [PIPE_LATENCY:0];        // filter r delayed value
    reg [7:0] filter_g_delayed [PIPE_LATENCY:0];        // filter g delayed value
    reg [7:0] filter_b_delayed [PIPE_LATENCY:0];        // filter b delayed value
    reg [7:0] sobel_value_delayed [PIPE_LATENCY:0];     // sobel value delayed value
    reg [7:0] canny_value_delayed [PIPE_LATENCY:0];     // canny value delayed value
    reg       filter_ready_delayed [PIPE_LATENCY:0];     // filter ready delayed
    reg       sobel_ready_delayed  [PIPE_LATENCY:0];     // sobel ready delayed
    reg       canny_ready_delayed  [PIPE_LATENCY:0];     // canny ready delayed
    integer i; 

    // ?뚯씠?꾨씪???뺣젹
    always @(posedge clk_25_vga) begin
        // ?꾨젅???쒖옉(Vsync 濡쒖슦) ??紐⑤뱺 吏???덉??ㅽ꽣 ?대━??
        if (vsync_raw == 1'b0) begin
            for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= 17'd0;
                activeArea_delayed[i] <= 1'b0;
                red_value_delayed[i] <= 8'd0;
                green_value_delayed[i] <= 8'd0;
                blue_value_delayed[i] <= 8'd0;
                gray_value_delayed[i] <= 8'd0;
                filtered_pixel_delayed[i] <= 24'd0;
                filter_r_delayed[i] <= 8'd0;
                filter_g_delayed[i] <= 8'd0;
                filter_b_delayed[i] <= 8'd0;
                sobel_value_delayed[i] <= 8'd0;
                canny_value_delayed[i] <= 8'd0;
                filter_ready_delayed[i] <= 1'b0;
                sobel_ready_delayed[i] <= 1'b0;
                canny_ready_delayed[i] <= 1'b0;
            end
        end else begin
            // 0?④퀎
            rdaddress_delayed[0] <= rdaddress_aligned;
            activeArea_delayed[0] <= activeArea_aligned;
            red_value_delayed[0] <= red_value;
            green_value_delayed[0] <= green_value;
            blue_value_delayed[0] <= blue_value;
            gray_value_delayed[0] <= gray_value;
            filtered_pixel_delayed[0] <= filtered_pixel;
            filter_r_delayed[0] <= filter_r_888;
            filter_g_delayed[0] <= filter_g_888;
            filter_b_delayed[0] <= filter_b_888;
            sobel_value_delayed[0] <= sobel_value;
            canny_value_delayed[0] <= canny_value;
            filter_ready_delayed[0] <= filter_ready2;
            sobel_ready_delayed[0]  <= sobel_ready;
            canny_ready_delayed[0]  <= canny_ready;
            
            // 1-PIPE_LATENCY ?④퀎 吏??泥댁씤
            for (i= 1; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= rdaddress_delayed[i-1];
                activeArea_delayed[i] <= activeArea_delayed[i-1];
                red_value_delayed[i] <= red_value_delayed[i-1];
                green_value_delayed[i] <= green_value_delayed[i-1];
                blue_value_delayed[i] <= blue_value_delayed[i-1];
                gray_value_delayed[i] <= gray_value_delayed[i-1];
                filtered_pixel_delayed[i] <= filtered_pixel_delayed[i-1];
                filter_r_delayed[i] <= filter_r_delayed[i-1];
                filter_g_delayed[i] <= filter_g_delayed[i-1];
                filter_b_delayed[i] <= filter_b_delayed[i-1];
                sobel_value_delayed[i] <= sobel_value_delayed[i-1];
                canny_value_delayed[i] <= canny_value_delayed[i-1];
                filter_ready_delayed[i] <= filter_ready_delayed[i-1];
                sobel_ready_delayed[i]  <= sobel_ready_delayed[i-1];
                canny_ready_delayed[i]  <= canny_ready_delayed[i-1];
            end
        end
    end

    // 媛?곗떆??釉붾윭 (洹몃젅?댁뒪耳??8鍮꾪듃)
    wire [7:0] gray_blur;
    wire [7:0] gray_blur2;  // 2李?媛?곗떆??寃곌낵
    gaussian_3x3_gray8 gaussian_gray_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .pixel_out(gray_blur),
        .filter_ready(filter_ready)
    );

    // 2李?媛?곗떆?? 1李?寃곌낵瑜??ㅼ떆 釉붾윭 泥섎━
    wire [16:0] rdaddress_gauss2 = rdaddress_delayed[GAUSS_LAT];
    wire        activeArea_gauss2 = activeArea_delayed[GAUSS_LAT];
    gaussian_3x3_gray8 gaussian_gray2_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_blur),
        .pixel_addr(rdaddress_gauss2),
        .vsync(vsync_raw),
        .active_area(activeArea_gauss2),
        .pixel_out(gray_blur2),
        .filter_ready(filter_ready2)
    );

    // ?뚮꺼 ?ｌ? 寃異?(洹몃젅?댁뒪耳??8鍮꾪듃)
    sobel_3x3_gray8 sobel_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_blur2),
        .pixel_addr(sobel_addr_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .threshold(sobel_threshold_btn),
        .pixel_out(sobel_value),
        .sobel_ready(sobel_ready)
    );

    // 罹먮땲 ?ｌ? 寃異?(?덉뒪?뚮━?쒖뒪留??곸슜, NMS ?앸왂) - 2李?媛?곗떆??寃곌낵 ?낅젰
    wire canny_ready;
    reg  [7:0] canny_thr_low  = 8'd24;  // 湲곕낯 ??? ?꾧퀎
    reg  [7:0] canny_thr_high = 8'd64;  // 湲곕낯 ?믪? ?꾧퀎
    // Sobel ?꾧퀎媛?諛??ㅼ쐞移??먯? 湲곕컲 利앷컧 ?쒖뼱
    reg  [7:0] sobel_threshold = 8'd64; // 珥덇린 64

    canny_3x3_gray8 canny_inst (
        .clk(clk_25_vga),
        .enable(filter_ready2),
        .pixel_in(gray_blur2),
        .pixel_addr(rdaddress_gauss2),
        .vsync(vsync_raw),
        .active_area(activeArea_gauss2),
        .threshold_low(canny_thr_low),
        .threshold_high(canny_thr_high),
        .pixel_out(canny_value),
        .canny_ready(canny_ready)
    );
    
    // ?됱긽 媛믩뱾 - RGB888 吏곸젒 ?ъ슜
    assign red_value   = activeArea_aligned ? r_888 : 8'h00;
    assign green_value = activeArea_aligned ? g_888 : 8'h00;
    assign blue_value  = activeArea_aligned ? b_888 : 8'h00;

    // 洹몃젅?댁뒪耳???ㅽ봽???몄깶??留덉뒪??
    wire signed [9:0] g_gray  = {2'b00, gray_value};
    wire signed [9:0] g_blur  = {2'b00, gray_blur};
    wire signed [10:0] g_unsharp_w = g_gray + ((g_gray - g_blur) >>> 1);
    wire [7:0] unsharp_gray = g_unsharp_w[10] ? 8'd0 : (g_unsharp_w > 11'sd255 ? 8'd255 : g_unsharp_w[7:0]);
    // For filter display, replicate 2-pass Gaussian output to RGB
    assign filtered_pixel = {gray_blur2, gray_blur2, gray_blur2};

    // ?ㅼ쐞移섏뿉 ?곕Ⅸ 異쒕젰 ?좏깮
    wire [7:0] final_r, final_g, final_b;

    // ?꾪꽣 ?곸슜???쎌??먯꽌 RGB 遺꾨━
    assign filter_r_888 = filtered_pixel[23:16];
    assign filter_g_888 = filtered_pixel[15:8];
    assign filter_b_888 = filtered_pixel[7:0];

    // 寃쎈줈蹂?吏???몃뜳??
    localparam integer IDX_ORIG  = PIPE_LATENCY;    // 理쒖쥌 寃쎈줈 ?뺣젹 ?몃뜳??(6)
    localparam integer IDX_GRAY  = PIPE_LATENCY;    // 理쒖쥌 寃쎈줈 ?뺣젹 ?몃뜳??(6)
    localparam integer IDX_GAUSS = PIPE_LATENCY - GAUSS_LAT;        // 媛?곗떆??異쒕젰 ?뺣젹 ?몃뜳??(4)
    localparam integer IDX_SOBEL = PIPE_LATENCY;    // ?뚮꺼? 2李?媛?곗떆????泥섎━?섎?濡??꾩껜 ?뚯씠?꾨씪??吏??(6)
    localparam integer IDX_CANNY = PIPE_LATENCY;    // 罹먮땲???꾩껜 ?뚯씠?꾨씪??6?대윮) ?꾩뿉 ?좏슚

    // 理쒖쥌 異쒕젰 ?좏깮(寃쎈줈蹂??몃뜳??諛?ready 寃뚯씠??
    wire [7:0] sel_orig_r = activeArea_delayed[IDX_ORIG] ? red_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_g = activeArea_delayed[IDX_ORIG] ? green_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_b = activeArea_delayed[IDX_ORIG] ? blue_value_delayed[IDX_ORIG] : 8'h00;

    wire [7:0] sel_gray   = activeArea_delayed[IDX_GRAY] ? gray_value_delayed[IDX_GRAY] : 8'h00;

    // 媛?곗떆??寃쎈줈: 寃쎄퀎?먯꽌??洹몃젅?댁뒪耳???⑥뒪?ㅻ（濡??泥?
    wire        gauss_active = activeArea_delayed[IDX_GAUSS];
    wire        gauss_ready  = filter_ready_delayed[IDX_GAUSS];
    wire [7:0]  gauss_gray_fallback = gray_value_delayed[IDX_GAUSS];
    // 寃쎄퀎/?뚮컢??援ш컙(filter_ready=0)? 寃??異쒕젰
    wire [7:0] sel_gauss_r = gauss_active ? (gauss_ready ? filter_r_delayed[IDX_GAUSS] : 8'h00) : 8'h00;
    wire [7:0] sel_gauss_g = gauss_active ? (gauss_ready ? filter_g_delayed[IDX_GAUSS] : 8'h00) : 8'h00;
    wire [7:0] sel_gauss_b = gauss_active ? (gauss_ready ? filter_b_delayed[IDX_GAUSS] : 8'h00) : 8'h00;

    wire [7:0] sel_sobel   = (activeArea_delayed[IDX_SOBEL] && sobel_ready_delayed[IDX_SOBEL]) ? sobel_value_delayed[IDX_SOBEL] : 8'h00;
    wire [7:0] sel_canny   = (activeArea_delayed[IDX_CANNY] && canny_ready_delayed[IDX_CANNY]) ? canny_value_delayed[IDX_CANNY] : 8'h00;

    assign final_r = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_r : sel_orig_r)));
    assign final_g = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_g : sel_orig_g)));
    assign final_b = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_b : sel_orig_b)));

    // ?쇱씤 ?쒖옉 ?곗씠???뚯씠?꾨씪???뚮컢??留덉뒪??
    // 媛??쇱씤 ?쒖옉(active ?곸듅)?먯꽌 ?곗씠??寃쎈줈 吏??TOTAL_DATA_LAT)留뚰겮 異쒕젰 留덉뒪??
    localparam integer TOTAL_DATA_LAT = PIPE_LATENCY + MEM_RD_LAT; // 6 + 2 = 8
    reg [TOTAL_DATA_LAT-1:0] line_valid_pipe = {TOTAL_DATA_LAT{1'b0}};
    reg [1:0] bram_settle_cnt = 2'd0;
    wire line_start_raw = activeArea && !activeArea_d1;

    always @(posedge clk_25_vga) begin
        if (!vga_enable) begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b0}};
            bram_settle_cnt <= 2'd0;
        end else if (line_start_raw) begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b0}};
            bram_settle_cnt <= 2'd0;
        end else if (activeArea) begin
            if (bram_settle_cnt < MEM_RD_LAT) begin
                bram_settle_cnt <= bram_settle_cnt + 1'b1;
                line_valid_pipe <= {line_valid_pipe[TOTAL_DATA_LAT-2:0], 1'b0};
            end else begin
                line_valid_pipe <= {line_valid_pipe[TOTAL_DATA_LAT-2:0], 1'b1};
            end
        end else begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b0}};
            bram_settle_cnt <= 2'd0;
        end
    end
    end
    wire line_warm_ok = line_valid_pipe[TOTAL_DATA_LAT-1];

    // VGA 異쒕젰 ?곌껐 (泥??꾨젅??罹≪쿂 ?꾨즺 ??+ ?쇱씤 ?뚮컢???댄썑 ?쒖꽦??
    assign vga_r = (vga_enable && line_warm_ok) ? final_r : 8'h00;  // 以鍮??덈릺硫?寃??異쒕젰
    assign vga_g = (vga_enable && line_warm_ok) ? final_g : 8'h00;
    assign vga_b = (vga_enable && line_warm_ok) ? final_b : 8'h00;

    // PLL ?몄뒪?댁뒪 - ?대윮 ?앹꽦
    my_altpll pll_inst (
        .inclk0(clk_50),
        .c0(clk_24_camera),
        .c1(clk_25_vga)
    );

    // VGA 而⑦듃濡ㅻ윭
    VGA vga_inst (
        .CLK25(clk_25_vga), 
        .pixel_data(rddata), 
        .clkout(vga_CLK),
        .Hsync(hsync_raw), 
        .Vsync(vsync_raw),
        .Nblank(vga_blank_N_raw), 
        .Nsync(vga_sync_N_raw),
        .activeArea(activeArea), 
        .pixel_address(rdaddress)
    );

    // VGA ?숆린???좏샇?ㅼ쓣 ?곗씠??寃쎈줈 吏?곌낵 ?쇱튂?쒗궎湲??꾪븳 ?뚯씠?꾨씪??
    // ?꾩껜 ?곗씠??吏??= 硫붾え由??쎄린 吏??2) + ?뚯씠?꾨씪??6) + 蹂댁젙(1+異붽?3) = 12?대윮
    localparam integer SYNC_DELAY = PIPE_LATENCY + MEM_RD_LAT + 4; // 12
    reg [SYNC_DELAY-1:0] hsync_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] vsync_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] nblank_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] nsync_delay_pipe = {SYNC_DELAY{1'b0}};
    always @(posedge clk_25_vga) begin
        hsync_delay_pipe  <= {hsync_delay_pipe[SYNC_DELAY-2:0], hsync_raw};
        vsync_delay_pipe  <= {vsync_delay_pipe[SYNC_DELAY-2:0], vsync_raw};
        nblank_delay_pipe <= {nblank_delay_pipe[SYNC_DELAY-2:0], vga_blank_N_raw};
        nsync_delay_pipe  <= {nsync_delay_pipe[SYNC_DELAY-2:0], vga_sync_N_raw};
    end

    assign vga_hsync   = hsync_delay_pipe[SYNC_DELAY-1];
    assign vga_vsync   = vsync_delay_pipe[SYNC_DELAY-1];
    assign vga_blank_N = nblank_delay_pipe[SYNC_DELAY-1];
    assign vga_sync_N  = nsync_delay_pipe[SYNC_DELAY-1];

    // OV7670 移대찓??而⑦듃濡ㅻ윭
    ov7670_controller camera_ctrl (
        .clk_50(clk_50),
        .clk_24(clk_24_camera),
        .resend(resend),
        .config_finished(led_config_finished),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .reset(ov7670_reset),
        .pwdn(ov7670_pwdn),
        .xclk(ov7670_xclk)
    );

    // OV7670 罹≪쿂 紐⑤뱢 (2x2 ?됯퇏 ?붿떆硫붿씠???ы븿)
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .addr(wraddress),
        .dout(wrdata),
        .we(wren)
    );

    // ????꾨젅??踰꾪띁 RAM??
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),
        .wraddress(wraddress_ram1),
        .wrclock(ov7670_pclk),
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1[15:0]),
        .rdclock(clk_25_vga),
        .q(rddata_ram1)
    );

    frame_buffer_ram buffer_ram2 (
        .data(wrdata_ram2),
        .wraddress(wraddress_ram2),
        .wrclock(ov7670_pclk),
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2[15:0]),
        .rdclock(clk_25_vga),
        .q(rddata_ram2)
    );

endmodule

